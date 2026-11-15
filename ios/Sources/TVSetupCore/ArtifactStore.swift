import Foundation
import CryptoKit

public enum ArtifactVerifier {
    public static func verify(_ file: URL, artifact: Artifact) throws {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256(); var count = 0
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            count += chunk.count
            guard count <= artifact.size else { throw SetupError.invalid("Download exceeds the pinned size.") }
            hash.update(data: chunk)
        }
        guard count == artifact.size, hex(hash.finalize()) == artifact.sha256 else { throw SetupError.invalid("Download does not match the pinned release. Nothing installed.") }
        guard try APKSigner.certificateHash(file: file) == artifact.signerSha256 else { throw SetupError.invalid("APK certificate differs from the pinned publisher.") }
    }
    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
}

/// Extracts v2 signer identity AFTER exact file-hash verification. This is not an
/// independent APK signature verifier. Release preparation also runs apksigner.
public enum APKSigner {
    public static func certificateHash(file: URL) throws -> String {
        try certificateHash(data: Data(contentsOf: file, options: .mappedIfSafe))
    }
    static func certificateHash(data: Data) throws -> String {
        guard data.count >= 22 else { throw SetupError.invalid("Truncated APK.") }
        func number(_ offset: Int, _ width: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - width else { throw SetupError.invalid("Invalid APK offset.") }
            var result: UInt64 = 0
            for i in 0..<width { result |= UInt64(data[offset + i]) << (i * 8) }
            guard result <= UInt64(Int.max) else { throw SetupError.invalid("Oversized APK field.") }
            return Int(result)
        }
        var eocd: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try number(offset, 4) == 0x06054b50, try number(offset + 20, 2) == data.count - offset - 22 { eocd = offset; break }
        }
        guard let eocd, let central = try? number(eocd + 16, 4), central >= 32, central <= eocd,
              data.subdata(in: (central - 16)..<central) == Data("APK Sig Block 42".utf8) else { throw SetupError.invalid("No supported APK v2 signing block.") }
        let blockSize = try number(central - 24, 8)
        guard blockSize >= 24, blockSize <= central - 8 else { throw SetupError.invalid("Invalid signing-block size.") }
        let start = central - blockSize - 8
        guard try number(start, 8) == blockSize else { throw SetupError.invalid("Signing-block lengths disagree.") }
        var position = start + 8
        while position < central - 24 {
            let length = try number(position, 8); position += 8
            guard length >= 4, length <= central - 24 - position else { throw SetupError.invalid("Invalid signing-block entry.") }
            let end = position + length
            if try number(position, 4) == 0x7109871a {
                var root = Cursor(data: data.subdata(in: (position + 4)..<end))
                var signers = try root.field()
                guard root.remaining == 0 else { throw SetupError.invalid("Trailing signer data.") }
                var signer = try signers.field()
                guard signers.remaining == 0 else { throw SetupError.invalid("Multiple APK signers are not supported.") }
                var signed = try signer.field()
                _ = try signed.field() // Digests, already protected by the pinned whole-file SHA256.
                var certificates = try signed.field()
                let certificate = try certificates.field()
                guard !certificate.data.isEmpty else { throw SetupError.invalid("Empty APK certificate.") }
                return ArtifactVerifier.hex(SHA256.hash(data: certificate.data))
            }
            position = end
        }
        throw SetupError.invalid("APK v2 signer not found.")
    }
    private struct Cursor {
        let data: Data; var offset = 0
        var remaining: Int { data.count - offset }
        mutating func field() throws -> Cursor {
            guard remaining >= 4 else { throw SetupError.invalid("Truncated signer field.") }
            var length: UInt32 = 0
            for i in 0..<4 { length |= UInt32(data[offset + i]) << (i * 8) }
            offset += 4
            guard Int(length) <= remaining else { throw SetupError.invalid("Invalid signer field length.") }
            let result = Cursor(data: data.subdata(in: offset..<(offset + Int(length))))
            offset += Int(length); return result
        }
    }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]
        completionHandler(request.url?.scheme == "https" && allowed.contains(request.url?.host ?? "") ? request : nil)
    }
}
public enum ArtifactStore {
    /// Caller removes the returned temporary file after installation.
    public static func fetch(_ artifact: Artifact, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apk")
        do {
            if artifact.url.hasPrefix("bundled:") {
                let name = String(artifact.url.dropFirst(8))
                guard name == "search-handoff-1.0.apk", let source = Bundle.module.url(forResource: "search-handoff-1.0", withExtension: "apk") else { throw SetupError.invalid("Missing bundled helper.") }
                try FileManager.default.copyItem(at: source, to: destination)
            } else {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 300
                let session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(from: URL(string: artifact.url)!)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.expectedContentLength == -1 || http.expectedContentLength == artifact.size else { throw SetupError.invalid("Publisher download is unavailable or has changed.") }
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let file = try FileHandle(forWritingTo: destination); defer { try? file.close() }
                var buffer = Data(); buffer.reserveCapacity(65_536); var count = 0
                for try await byte in bytes {
                    try Task.checkCancellation()
                    count += 1
                    guard count <= artifact.size else { throw SetupError.invalid("Download exceeded the pinned size.") }
                    buffer.append(byte)
                    if buffer.count == 65_536 { try file.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true); progress(count, artifact.size) }
                }
                try file.write(contentsOf: buffer)
            }
            try ArtifactVerifier.verify(destination, artifact: artifact)
            progress(artifact.size, artifact.size)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination); throw error
        }
    }
}
