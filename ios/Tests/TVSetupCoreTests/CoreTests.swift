import XCTest
import CryptoKit
import SwiftADB
@testable import TVSetupCore

final class CoreTests: XCTestCase {
    func testCatalogAndArchitectureSelection() throws {
        let catalog = try Catalog.bundled()
        let tv = TV(model: "Example TV", sdk: 30, abis: ["armeabi-v7a"], installed: [], isTV: true)
        let plan = try Planner.make(catalog: catalog, tv: tv, selected: ["tizentube", "voice", "proton"])
        XCTAssertEqual(plan.compactMap(\.artifact).map(\.id), ["tizentube-arm", "search-handoff", "proton"])
        let arm64 = TV(model: "64-bit", sdk: 30, abis: ["arm64-v8a", "armeabi-v7a"], installed: [], isTV: true)
        XCTAssertEqual(try Planner.make(catalog: catalog, tv: arm64, selected: ["tizentube"]).first?.artifact?.id, "tizentube-arm64")
    }
    func testExistingAppsAreNeverReplaced() throws {
        let catalog = try Catalog.bundled()
        let installed = Set(catalog.features.flatMap(\.artifacts).map(\.package))
        let tv = TV(model: "Existing", sdk: 30, abis: ["armeabi-v7a"], installed: installed, isTV: true)
        XCTAssertTrue(try Planner.make(catalog: catalog, tv: tv, selected: ["tizentube", "voice", "proton"]).allSatisfy { $0.artifact == nil })
    }
    func testIncompatiblePlanFailsBeforeAnyInstall() throws {
        let catalog = try Catalog.bundled()
        let api24 = TV(model: "Older", sdk: 24, abis: ["armeabi-v7a"], installed: [], isTV: true)
        XCTAssertThrowsError(try Planner.make(catalog: catalog, tv: api24, selected: ["tizentube", "proton"]))
        let x86 = TV(model: "Other", sdk: 30, abis: ["x86"], installed: [], isTV: true)
        XCTAssertThrowsError(try Planner.make(catalog: catalog, tv: x86, selected: ["tizentube"]))
        let phone = TV(model: "Phone", sdk: 30, abis: ["armeabi-v7a"], installed: [], isTV: false)
        XCTAssertThrowsError(try Planner.make(catalog: catalog, tv: phone, selected: ["proton"]))
        XCTAssertThrowsError(try Planner.make(catalog: catalog, tv: api24, selected: ["voice"]))
        XCTAssertThrowsError(try Planner.make(catalog: catalog, tv: api24, selected: []))
        XCTAssertThrowsError(try Planner.make(catalog: catalog, tv: api24, selected: ["unknown"]))
    }
    func testOnlyExplicitPrivateEndpoints() throws {
        for host in ["10.8.7.6", "172.16.0.8", "172.31.255.254", "192.168.8.7"] { XCTAssertNoThrow(try Endpoint(host: host)) }
        for host in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "169.254.1.1", "172.32.0.1", "224.0.0.1", "tv.local", "localhost", "10.8.7.6;reboot", "10.0.0.999", "10..0.1", "::1"] { XCTAssertThrowsError(try Endpoint(host: host)) }
        for port in ["0", "65536", "-1", "5555;reboot"] { XCTAssertThrowsError(try Endpoint(host: "10.8.7.6", port: port)) }
    }
    func testCatalogRejectsUntrustedOrInvalidMetadata() throws {
        let original = try JSONEncoder().encode(Catalog.bundled())
        let root = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        for (key, value) in [("url", "http://github.com/a/b/releases/download/v1/a.apk"), ("url", "https://example.com/a.apk"), ("url", "https://github.com/a/b/releases/download/latest/a.apk"), ("url", "bundled:private.apk"), ("package", "a.b;reboot"), ("sha256", "invalid")] {
            var changed = root; var features = changed["features"] as! [[String: Any]]; var artifacts = features[0]["artifacts"] as! [[String: Any]]
            artifacts[0][key] = value; features[0]["artifacts"] = artifacts; changed["features"] = features
            XCTAssertThrowsError(try Catalog.load(JSONSerialization.data(withJSONObject: changed)), key)
        }
    }
    func testBundledHelperHashAndCertificate() async throws {
        let artifact = try Catalog.bundled().features.first { $0.id == "voice" }!.artifacts[0]
        let file = try await ArtifactStore.fetch(artifact); defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try APKSigner.certificateHash(file: file), artifact.signerSha256)
        var bytes = try Data(contentsOf: file); bytes[200] ^= 1; try bytes.write(to: file)
        XCTAssertThrowsError(try ArtifactVerifier.verify(file, artifact: artifact))
    }
    func testOfficialReleaseAPKsWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment["TVSETUP_RELEASE_APK_DIR"] else { throw XCTSkip("Set TVSETUP_RELEASE_APK_DIR to reviewed local release fixtures; never downloads in tests.") }
        for artifact in try Catalog.bundled().features.flatMap(\.artifacts) where !artifact.url.hasPrefix("bundled:") {
            try ArtifactVerifier.verify(URL(fileURLWithPath: directory).appendingPathComponent(artifact.id + ".apk"), artifact: artifact)
        }
    }
    func testMalformedAPKDoesNotCrash() {
        for count in [0, 1, 21, 22, 64, 65_557] { XCTAssertThrowsError(try APKSigner.certificateHash(data: Data(repeating: 0xff, count: count))) }
    }
    func testPacketBoundsMagicChecksumAndPartialReads() throws {
        let valid = AdbProtocol.generateWrite(localId: 1, remoteId: 2, data: Data("hello".utf8))
        for length in 0..<valid.count { XCTAssertNil(try Packet.parse(from: valid.prefix(length), protocolVersion: AdbProtocol.aVersionMin, maxData: 4096)) }
        XCTAssertEqual(try Packet.parse(from: valid, protocolVersion: AdbProtocol.aVersionMin, maxData: 4096)?.message.payload, Data("hello".utf8))
        var corrupt = valid; corrupt[20] ^= 1
        XCTAssertThrowsError(try Packet.parse(from: corrupt, protocolVersion: AdbProtocol.aVersionMin, maxData: 4096))
        corrupt = valid; corrupt[24] ^= 1
        XCTAssertThrowsError(try Packet.parse(from: corrupt, protocolVersion: AdbProtocol.aVersionMin, maxData: 4096))
        corrupt = valid; for i in 12..<16 { corrupt[i] = 255 }
        XCTAssertThrowsError(try Packet.parse(from: corrupt, protocolVersion: AdbProtocol.aVersionMin, maxData: 4096))
    }
}

private func packet(_ command: UInt32, _ a: UInt32 = 0, _ b: UInt32 = 0, _ data: Data? = nil) -> Packet {
    try! Packet.parse(from: AdbProtocol.generateMessage(command: command, arg0: a, arg1: b, data: data), protocolVersion: AdbProtocol.aVersionMin, maxData: 262_144)!.message
}
private func shellReply(_ id: UInt32, _ text: String) -> [Packet] {
    let remote = id + 100
    return [packet(AdbProtocol.aOkay, remote, id), packet(AdbProtocol.aWrte, remote, id, Data(text.utf8)), packet(AdbProtocol.aClse, remote, id)]
}
private actor FakeTransport: PacketTransport {
    var incoming: [Packet]; var outgoing: [Data] = []; var closed = false
    init(_ incoming: [Packet]) { self.incoming = incoming }
    func connect() throws { if closed { throw SetupError.invalid("Closed") } }
    func send(_ data: Data) throws { if closed { throw SetupError.invalid("Closed") }; outgoing.append(data) }
    func receive() throws -> Packet { guard !closed, !incoming.isEmpty else { throw SetupError.invalid("Fake peer ended") }; return incoming.removeFirst() }
    func close() { closed = true }
    func sent() throws -> [Packet] { try outgoing.map { try Packet.parse(from: $0, protocolVersion: AdbProtocol.aVersionMin, maxData: 262_144)!.message } }
}
final class TransportTests: XCTestCase {
    func testAuthorizationSignsThenOffersPublicKey() async throws {
        let fake = FakeTransport([packet(AdbProtocol.aAuth, 1, 0, Data(repeating: 3, count: 20)), packet(AdbProtocol.aAuth, 1, 0, Data(repeating: 4, count: 20)), packet(AdbProtocol.aCnxn, AdbProtocol.aVersionMin, 4096)])
        let session = LegacyADB(transport: fake, key: try KeyPair.generate()); try await session.connect()
        let sent = try await fake.sent()
        XCTAssertEqual(sent.map(\.command), [AdbProtocol.aCnxn, AdbProtocol.aAuth, AdbProtocol.aAuth])
        XCTAssertEqual(sent.dropFirst().map(\.arg0), [2, 3]); XCTAssertEqual(sent[1].payload?.count, 256)
        XCTAssertTrue(String(decoding: sent[2].payload!, as: UTF8.self).contains("TVSetup"))
    }
    func testTLSIsNotSilentlyDowngraded() async throws {
        let fake = FakeTransport([packet(AdbProtocol.aStls)])
        let session = LegacyADB(transport: fake, key: try KeyPair.generate())
        do { try await session.connect(); XCTFail("Expected refusal") } catch {}
        let closed = await fake.closed; XCTAssertTrue(closed)
    }
    func testReadOnlyProbeDoesNotRunSettingsOrAppCommands() async throws {
        let catalog = try Catalog.bundled()
        var replies = [packet(AdbProtocol.aCnxn, AdbProtocol.aVersionMin, 4096)]
        for (i, text) in ["0\n", "Example TV\n", "30\n", "armeabi-v7a\n", "feature:android.software.leanback\n", "package:ch.protonvpn.android\n", "", ""].enumerated() { replies += shellReply(UInt32(i + 1), text) }
        let fake = FakeTransport(replies); let session = LegacyADB(transport: fake, key: try KeyPair.generate())
        try await session.connect(); let tv = try await session.probe(catalog: catalog)
        XCTAssertEqual(tv.installed, ["ch.protonvpn.android"]); XCTAssertTrue(tv.isTV)
        let commands = try await fake.sent().filter { $0.command == AdbProtocol.aOpen }.map { String(decoding: $0.payload!.dropLast(), as: UTF8.self) }
        XCTAssertEqual(commands.count, 8)
        XCTAssertTrue(commands.allSatisfy { $0.hasPrefix("shell:getprop ") || $0 == "shell:am get-current-user" || $0 == "shell:pm list features" || $0.hasPrefix("shell:pm list packages ") })
    }
    func testInstallTransfersExactBytesAcknowledgesAndChecksPackage() async throws {
        let artifact = try Catalog.bundled().features.first { $0.id == "voice" }!.artifacts[0]
        let file = try await ArtifactStore.fetch(artifact); defer { try? FileManager.default.removeItem(at: file) }
        var replies = [packet(AdbProtocol.aCnxn, AdbProtocol.aVersionMin, 4096)] + shellReply(1, "")
        replies += [packet(AdbProtocol.aOkay, 102, 2)]
        for _ in 0..<((artifact.size + 4095) / 4096) { replies.append(packet(AdbProtocol.aOkay, 102, 2)) }
        replies += [packet(AdbProtocol.aWrte, 102, 2, Data("Success\n".utf8)), packet(AdbProtocol.aClse, 102, 2)] + shellReply(3, "package:\(artifact.package)\n")
        let fake = FakeTransport(replies); let session = LegacyADB(transport: fake, key: try KeyPair.generate())
        try await session.connect(); let result = try await session.install(file, artifact: artifact)
        XCTAssertEqual(result, "Installed and confirmed")
        let sent = try await fake.sent(); let writes = sent.filter { $0.command == AdbProtocol.aWrte }
        XCTAssertEqual(writes.reduce(Data()) { $0 + ($1.payload ?? Data()) }, try Data(contentsOf: file))
        XCTAssertTrue(writes.allSatisfy { ($0.payload?.count ?? 0) <= 4096 })
        let commands = sent.filter { $0.command == AdbProtocol.aOpen }.map { String(decoding: $0.payload!.dropLast(), as: UTF8.self) }
        XCTAssertEqual(commands[1], "exec:cmd package install --user 0 -S \(artifact.size)")
        XCTAssertFalse(commands.contains { $0.contains(" -r") })
    }
    func testExistingPackageSkipsInstallerEntirely() async throws {
        let artifact = try Catalog.bundled().features.first { $0.id == "voice" }!.artifacts[0]
        let file = try await ArtifactStore.fetch(artifact); defer { try? FileManager.default.removeItem(at: file) }
        let fake = FakeTransport([packet(AdbProtocol.aCnxn, AdbProtocol.aVersionMin, 4096)] + shellReply(1, "package:\(artifact.package)\n"))
        let session = LegacyADB(transport: fake, key: try KeyPair.generate()); try await session.connect()
        let result = try await session.install(file, artifact: artifact); XCTAssertEqual(result, "Kept existing app unchanged")
        let sent = try await fake.sent(); XCTAssertEqual(sent.filter { $0.command == AdbProtocol.aOpen }.count, 1)
    }
    func testMismatchedStreamClosesSocket() async throws {
        let fake = FakeTransport([packet(AdbProtocol.aCnxn, AdbProtocol.aVersionMin, 4096), packet(AdbProtocol.aOkay, 10, 99)])
        let session = LegacyADB(transport: fake, key: try KeyPair.generate()); try await session.connect()
        do { _ = try await session.probe(catalog: Catalog.bundled()); XCTFail("Expected stream error") } catch {}
        let closed = await fake.closed; XCTAssertTrue(closed)
    }
}
