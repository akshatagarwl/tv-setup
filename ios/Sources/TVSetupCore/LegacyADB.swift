import Foundation
import Network
import Security
import SwiftADB

typealias Packet = AdbProtocol.Message
protocol PacketTransport: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Packet
    func close() async
}

/// A deadline also closes the socket, unblocking Network.framework continuations.
private func bounded<T: Sendable>(_ seconds: Double, abort: @escaping @Sendable () -> Void, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            abort(); throw SetupError.invalid("TV connection timed out. Check network debugging, Local Network permission and the authorization prompt.")
        }
        do { let result = try await group.next()!; group.cancelAll(); return result }
        catch { abort(); group.cancelAll(); throw error }
    }
}
private final class Once: @unchecked Sendable {
    private let lock = NSLock(); private var finished = false
    func run(_ action: () -> Void) { lock.lock(); let shouldRun = !finished; finished = true; lock.unlock(); if shouldRun { action() } }
}
private actor NetworkTransport: PacketTransport {
    let socket: NWConnection
    init(endpoint: Endpoint) {
        let options = NWProtocolTCP.Options(); options.noDelay = true
        socket = NWConnection(host: NWEndpoint.Host(endpoint.host), port: NWEndpoint.Port(rawValue: endpoint.port)!, using: NWParameters(tls: nil, tcp: options))
    }
    func connect() async throws {
        let socket = self.socket
        try await bounded(60, abort: { socket.cancel() }) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = Once()
                socket.stateUpdateHandler = { state in
                    switch state {
                    case .ready: once.run { continuation.resume() }
                    case .failed(let error): once.run { continuation.resume(throwing: error) }
                    case .cancelled: once.run { continuation.resume(throwing: SetupError.invalid("Connection cancelled.")) }
                    default: break
                    }
                }
                socket.start(queue: .global())
            }
        }
        socket.stateUpdateHandler = nil
    }
    func send(_ data: Data) async throws {
        let socket = self.socket
        try await bounded(30, abort: { socket.cancel() }) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                socket.send(content: data, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        }
    }
    func receive() async throws -> Packet {
        let socket = self.socket
        return try await bounded(60, abort: { socket.cancel() }) {
            try await AdbProtocol.parse(connection: socket, protocolVersion: AdbProtocol.aVersionMin, maxData: 262_144)
        }
    }
    func close() { socket.cancel() }
}

public enum PhoneKeyStore {
    public static func loadOrCreate() throws -> KeyPair {
        let tag = Data("io.akshat.tvsetup.adb.v1".utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag,
                                   kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecReturnRef as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let result {
            let key = result as! SecKey
            guard let publicKey = SecKeyCopyPublicKey(key) else { throw SetupError.invalid("Cannot load the phone's ADB identity.") }
            return KeyPair(privateKey: key, publicKey: publicKey)
        }
        guard status == errSecItemNotFound else { throw SetupError.invalid("Unlock the phone to access its ADB identity.") }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: tag,
                                           kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error), let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SetupError.invalid("Could not create the phone's private ADB identity.")
        }
        return KeyPair(privateKey: privateKey, publicKey: publicKey)
    }
}

/// Serial, one-stream-at-a-time ADB client. No arbitrary shell, TLS downgrade,
/// key filtering, package removal, reinstall, profile access or settings writes.
public actor LegacyADB {
    private let transport: any PacketTransport
    private let key: KeyPair
    private var connected = false
    private var busy = false
    private var nextID: UInt32 = 0
    private var maxData = 4096
    public static func make(endpoint: Endpoint) throws -> LegacyADB {
        LegacyADB(transport: NetworkTransport(endpoint: endpoint), key: try PhoneKeyStore.loadOrCreate())
    }
    init(transport: any PacketTransport, key: KeyPair) { self.transport = transport; self.key = key }
    public func connect() async throws {
        guard !busy, !connected else { throw SetupError.invalid("A connection is already in progress.") }
        busy = true; defer { busy = false }
        do {
            try await transport.connect()
            try await transport.send(AdbProtocol.generateConnect(api: 24))
            var signed = false
            for _ in 0..<5 {
                let packet = try await transport.receive()
                if packet.command == AdbProtocol.aCnxn {
                    guard packet.arg1 > 0 else { throw SetupError.invalid("TV advertised an invalid ADB packet size.") }
                    maxData = min(Int(packet.arg1), 262_144); connected = true; return
                }
                guard packet.command == AdbProtocol.aAuth, packet.arg0 == 1, let challenge = packet.payload, challenge.count == 20 else {
                    throw SetupError.invalid("This preview supports classic network ADB only, not wireless-debugging pairing/TLS ports.")
                }
                let payload = try signed ? AndroidPubkey.encodeWithName(publicKey: key.publicKey, name: "TVSetup") : key.sign(token: challenge)
                try await transport.send(AdbProtocol.generateAuth(type: signed ? 3 : 2, data: payload)); signed = true
            }
            throw SetupError.invalid("TV authorization was not completed.")
        } catch { await close(); throw error }
    }
    public func close() async { connected = false; await transport.close() }
    private func claim() throws {
        guard connected, !busy else { throw SetupError.invalid("Connect to one TV and wait for the current operation to finish.") }
        busy = true
    }
    public func probe(catalog: Catalog) async throws -> TV {
        try claim(); defer { busy = false }
        guard try await shell("am get-current-user").trimmingCharacters(in: .whitespacesAndNewlines) == "0" else { throw SetupError.invalid("Use the TV's owner profile for this preview.") }
        let model = try await shell("getprop ro.product.model").trimmingCharacters(in: .whitespacesAndNewlines)
        let sdkText = try await shell("getprop ro.build.version.sdk").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sdk = Int(sdkText) else { throw SetupError.invalid("Could not read the TV's Android version.") }
        let abis = try await shell("getprop ro.product.cpu.abilist").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
        let features = try await shell("pm list features")
        var installed = Set<String>()
        for package in Set(catalog.features.flatMap(\.artifacts).map(\.package)).sorted() {
            if try await isInstalled(package) { installed.insert(package) }
        }
        return TV(model: String(model.prefix(120)), sdk: sdk, abis: abis, installed: installed,
                  isTV: features.contains("feature:android.software.leanback") || features.contains("feature:android.hardware.type.television"))
    }
    public func install(_ file: URL, artifact: Artifact) async throws -> String {
        try claim(); defer { busy = false }
        // Verify again directly before privileged use, not merely after download.
        try ArtifactVerifier.verify(file, artifact: artifact)
        if try await isInstalled(artifact.package) { return "Kept existing app unchanged" }
        let output = try await stream(destination: "exec:cmd package install --user 0 -S \(artifact.size)", file: file)
        guard output.split(whereSeparator: \.isNewline).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Success" }),
              try await isInstalled(artifact.package) else { throw SetupError.invalid("Installation did not report success. Reconnect to check the TV; no existing app was replaced.") }
        return "Installed and confirmed"
    }
    private func isInstalled(_ package: String) async throws -> Bool {
        guard package.range(of: "^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$", options: .regularExpression) != nil else { throw SetupError.invalid("Invalid package name.") }
        return try await shell("pm list packages \(package)").split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == "package:\(package)" }
    }
    private func shell(_ command: String) async throws -> String { try await stream(destination: "shell:" + command, file: nil) }
    private func stream(destination: String, file: URL?) async throws -> String {
        nextID += 1; let local = nextID
        do {
            try await transport.send(AdbProtocol.generateOpen(localId: local, destination: destination))
            let opened = try await transport.receive()
            guard opened.command == AdbProtocol.aOkay, opened.arg1 == local else { throw SetupError.invalid("TV rejected the requested operation.") }
            let remote = opened.arg0
            var result = Data()
            func add(_ packet: Packet) async throws {
                guard packet.arg0 == remote, packet.arg1 == local else { throw SetupError.invalid("Mismatched ADB stream.") }
                if packet.command == AdbProtocol.aWrte {
                    guard result.count + (packet.payload?.count ?? 0) <= 65_536 else { throw SetupError.invalid("TV response exceeded its limit.") }
                    result.append(packet.payload ?? Data())
                    try await transport.send(AdbProtocol.generateReady(localId: local, remoteId: remote))
                }
            }
            if let file {
                let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
                while let data = try input.read(upToCount: maxData), !data.isEmpty {
                    try Task.checkCancellation()
                    try await transport.send(AdbProtocol.generateWrite(localId: local, remoteId: remote, data: data))
                    while true {
                        let reply = try await transport.receive()
                        try await add(reply)
                        if reply.command == AdbProtocol.aOkay { break }
                        guard reply.command == AdbProtocol.aWrte else { throw SetupError.invalid("TV stopped installation before all bytes arrived.") }
                    }
                }
            }
            while true {
                let reply = try await transport.receive()
                try await add(reply)
                if reply.command == AdbProtocol.aClse {
                    try await transport.send(AdbProtocol.generateClose(localId: local, remoteId: remote)); break
                }
                guard reply.command == AdbProtocol.aWrte || reply.command == AdbProtocol.aOkay else { throw SetupError.invalid("Unexpected TV response.") }
            }
            return String(decoding: result, as: UTF8.self)
        } catch { await close(); throw error }
    }
}
