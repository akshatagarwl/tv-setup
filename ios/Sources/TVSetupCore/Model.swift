import Foundation

public enum SetupError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public struct Artifact: Codable, Sendable, Identifiable {
    public let id: String
    public let package: String
    public let version: String
    public let minSdk: Int
    public let abis: [String]
    public let size: Int
    public let sha256: String
    public let signerSha256: String
    public let url: String
    public let source: String
}
public struct Feature: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let manual: String
    public let requires: [String]?
    public let artifacts: [Artifact]
}
public struct Catalog: Codable, Sendable {
    public let schema: Int
    public let release: String
    public let features: [Feature]
    public static func notices() -> String {
        guard let url = Bundle.module.url(forResource: "NOTICES", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "License resource is missing." }
        return text
    }
    public static func bundled() throws -> Catalog {
        try load(Data(contentsOf: Bundle.module.url(forResource: "catalog", withExtension: "json")!))
    }
    public static func load(_ data: Data) throws -> Catalog {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.schema == 1, !catalog.features.isEmpty,
              Set(catalog.features.map(\.id)).count == catalog.features.count else { throw SetupError.invalid("Invalid catalog.") }
        var ids = Set<String>()
        for feature in catalog.features {
            guard !feature.artifacts.isEmpty, (feature.requires ?? []).allSatisfy({ dependency in
                dependency != feature.id && catalog.features.contains { $0.id == dependency }
            }) else { throw SetupError.invalid("Invalid feature dependencies.") }
            for artifact in feature.artifacts {
                guard ids.insert(artifact.id).inserted,
                      artifact.package.range(of: "^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$", options: .regularExpression) != nil,
                      artifact.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      artifact.signerSha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      (1...200_000_000).contains(artifact.size), (24...100).contains(artifact.minSdk),
                      artifact.source.hasPrefix("https://github.com/"), URL(string: artifact.source) != nil,
                      artifact.url == "bundled:search-handoff-1.0.apk" || validReleaseURL(artifact.url) else {
                    throw SetupError.invalid("Invalid artifact metadata.")
                }
            }
        }
        return catalog
    }
    private static func validReleaseURL(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return false }
        let parts = url.pathComponents
        return parts.count == 7 && parts[3] == "releases" && parts[4] == "download" && !["latest", "main", "master"].contains(parts[5]) && parts[6].hasSuffix(".apk")
    }
}

public struct Endpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    public init(host: String, port: String = "5555") throws {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && $0.count <= 3 }),
              let a = UInt8(parts[0]), let b = UInt8(parts[1]), let c = UInt8(parts[2]), let d = UInt8(parts[3]),
              a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168),
              let parsedPort = UInt16(port), parsedPort > 0 else {
            throw SetupError.invalid("Enter the TV's private IPv4 address and ADB port. Public addresses, hostnames and pairing-code ports are not supported in this preview.")
        }
        self.host = "\(a).\(b).\(c).\(d)"; self.port = parsedPort
    }
}

public struct TV: Sendable {
    public let model: String
    public let sdk: Int
    public let abis: [String]
    public let installed: Set<String>
    public let isTV: Bool
    public func addingInstalledPackage(_ package: String) -> TV {
        TV(model: model, sdk: sdk, abis: abis, installed: installed.union([package]), isTV: isTV)
    }
}
public struct PlanItem: Identifiable, Sendable {
    public var id: String { feature.id }
    public let feature: Feature
    public let artifact: Artifact?
    public let status: String
}
public enum Planner {
    public static func make(catalog: Catalog, tv: TV, selected: Set<String>) throws -> [PlanItem] {
        guard tv.isTV else { throw SetupError.invalid("This device does not report Android TV support. Nothing will be installed.") }
        guard !selected.isEmpty, selected.isSubset(of: Set(catalog.features.map(\.id))) else { throw SetupError.invalid("Choose at least one supported feature.") }
        for feature in catalog.features where selected.contains(feature.id) {
            guard Set(feature.requires ?? []).isSubset(of: selected) else { throw SetupError.invalid("\(feature.name) also requires TizenTube to be selected.") }
        }
        return try catalog.features.filter { selected.contains($0.id) }.map { feature in
            if feature.artifacts.contains(where: { tv.installed.contains($0.package) }) {
                return PlanItem(feature: feature, artifact: nil, status: "Keep existing app unchanged")
            }
            guard let artifact = feature.artifacts.first(where: { tv.sdk >= $0.minSdk && ($0.abis.isEmpty || !$0.abis.filter(tv.abis.contains).isEmpty) }) else {
                throw SetupError.invalid("\(feature.name) is not supported on this TV's Android version or CPU. Nothing will be installed.")
            }
            return PlanItem(feature: feature, artifact: artifact, status: "Install \(artifact.version) (\(artifact.size / 1_000_000) MB)")
        }
    }
}
