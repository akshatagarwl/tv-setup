import SwiftUI
import UIKit
import TVSetupCore

@main
struct TVSetupApp: App {
    var body: some Scene { WindowGroup { SetupView() } }
}

@MainActor final class SetupModel: ObservableObject {
    @Published var host = ""
    @Published var port = "5555"
    @Published var selected = Set<String>()
    @Published var tv: TV?
    @Published var plan: [PlanItem] = []
    @Published var ready = false
    @Published var busy = false
    @Published var status = "Nothing is connected. Your TV will not change until you approve installation."
    @Published var results: [String] = []
    let catalog: Catalog?
    private var client: LegacyADB?
    private var worker: Task<Void, Never>?
    private var generation = UUID()
    init() {
        do { catalog = try Catalog.bundled() }
        catch { catalog = nil; status = "The bundled catalog is invalid. Setup is disabled." }
    }
    func changed() { plan = []; ready = false; results = [] }
    func connect() {
        guard let catalog, !busy else { return }
        changed(); tv = nil; busy = true
        let attempt = UUID(); generation = attempt
        status = "Connecting. Allow Local Network access on your phone, then approve this phone on the TV."
        worker = Task {
            do {
                if let client { await client.close() }
                let endpoint = try Endpoint(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port)
                let session = try LegacyADB.make(endpoint: endpoint); client = session
                try await session.connect()
                let info = try await session.probe(catalog: catalog)
                guard generation == attempt else { return }
                tv = info
                status = info.isTV ? "Connected. Compatibility check finished; no apps or settings changed." : "This is not a supported Android TV. Installation is disabled."
            } catch {
                guard generation == attempt else { return }
                if let client { await client.close() }; client = nil
                status = error.localizedDescription
            }
            if generation == attempt { busy = false }
        }
    }
    func preview() {
        changed()
        guard let catalog, let tv else { return }
        do { plan = try Planner.make(catalog: catalog, tv: tv, selected: selected); status = "Review every item below. Existing apps, accounts and settings will be kept." }
        catch { status = error.localizedDescription }
    }
    func install() {
        guard ready, !busy, !plan.isEmpty, let client else { return }
        let approvedPlan = plan; let attempt = generation
        busy = true; results = []
        UIApplication.shared.isIdleTimerDisabled = true
        worker = Task {
            defer { if generation == attempt { UIApplication.shared.isIdleTimerDisabled = false } }
            do {
                for item in approvedPlan {
                    try Task.checkCancellation()
                    guard generation == attempt else { return }
                    guard let artifact = item.artifact else { results.append("\(item.feature.name): kept unchanged"); continue }
                    status = "Downloading and checking \(item.feature.name)…"
                    let file = try await ArtifactStore.fetch(artifact)
                    defer { try? FileManager.default.removeItem(at: file) }
                    guard generation == attempt else { return }
                    status = "Installing \(item.feature.name). Keep this app open."
                    let result = try await client.install(file, artifact: artifact)
                    guard generation == attempt else { return }
                    tv = tv?.addingInstalledPackage(artifact.package)
                    results.append("\(item.feature.name): \(result)")
                }
                if generation == attempt { status = "Finished. Follow the TV steps below when convenient. Installation does not mean sign-in, permissions or playback have been verified." }
            } catch {
                guard generation == attempt else { return }
                await client.close(); self.client = nil; tv = nil; plan = []
                status = "Stopped: \(error.localizedDescription) Reconnect and preview again to see which apps are installed."
            }
            if generation == attempt { busy = false; ready = false }
        }
    }
    func disconnect() {
        generation = UUID(); worker?.cancel(); worker = nil
        let old = client; client = nil
        Task { await old?.close() }
        busy = false; tv = nil; changed()
        UIApplication.shared.isIdleTimerDisabled = false
        status = "Disconnected. A partially completed installation may have finished; reconnect to check. Existing apps were not replaced."
    }
}

struct SetupView: View {
    @StateObject private var model = SetupModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("A calmer TV, from your phone", systemImage: "tv")
                        .font(.title2.bold()).padding(.vertical, 6)
                    Text("Preview build • classic network ADB only").font(.caption).foregroundStyle(.secondary)
                    Text("Same trusted Wi-Fi. Enable network debugging on the TV first. Pairing-code-only TVs are not supported yet. The TV may show an authorization prompt when you connect.")
                }
                Section("1 · Connect and check") {
                    TextField("TV IPv4 address", text: $model.host).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy || model.tv != nil)
                    TextField("ADB port", text: $model.port).keyboardType(.numberPad).disabled(model.busy || model.tv != nil)
                    Button("Connect and read compatibility", action: model.connect).disabled(model.busy || model.tv != nil || model.catalog == nil)
                    if let tv = model.tv { Text("\(tv.model) · Android API \(tv.sdk) · \(tv.abis.joined(separator: ", "))").font(.caption) }
                }
                Section("2 · Choose what to install") {
                    ForEach(model.catalog?.features ?? []) { feature in
                        Toggle(isOn: Binding(get: { model.selected.contains(feature.id) }, set: { enabled in
                            if enabled { model.selected.insert(feature.id); for dependency in feature.requires ?? [] { model.selected.insert(dependency) } }
                            else { model.selected.remove(feature.id); if feature.id == "tizentube" { model.selected.remove("voice") } }
                            model.changed()
                        })) {
                            VStack(alignment: .leading, spacing: 5) { Text(feature.name).bold(); Text(feature.description).font(.caption).foregroundStyle(.secondary) }
                        }.disabled(model.busy)
                    }
                    Button("Preview changes", action: model.preview).disabled(model.busy || model.tv?.isTV != true || model.selected.isEmpty)
                    Text("Private channel lists, launcher changes and automatic permission grants are not included in this preview.").font(.caption).foregroundStyle(.secondary)
                }
                if !model.plan.isEmpty {
                    Section("3 · Review and approve") {
                        ForEach(model.plan) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.feature.name).bold(); Text(item.status)
                                if let artifact = item.artifact {
                                    Link("Source and release", destination: URL(string: artifact.source)!).font(.caption)
                                    Text("SHA256: \(artifact.sha256)").font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                                }
                            }
                        }
                        Toggle("The TV is not in use. I approve installing the missing apps shown above.", isOn: $model.ready).disabled(model.busy)
                        Button("Install approved apps", action: model.install).disabled(model.busy || !model.ready)
                        Text("No factory reset, app removal, replacement, automatic launch, accessibility changes or VPN connection. Keep the phone unlocked and this app open.").font(.caption)
                    }
                }
                Section("Status") {
                    if model.busy { ProgressView() }
                    Text(model.status).accessibilityIdentifier("setupStatus")
                    ForEach(Array(model.results.enumerated()), id: \.offset) { _, text in Text(text).font(.caption) }
                    Button("Disconnect / cancel", role: .destructive, action: model.disconnect).disabled(model.tv == nil && !model.busy)
                }
                if !model.results.isEmpty {
                    Section("Finish on the TV, when ready") { ForEach(model.plan) { item in Text("\(item.feature.name): \(item.feature.manual)") } }
                    Section("Undo") { Text("Only for apps marked Installed in this run: open TV Settings → Apps and disable the new app if supported. Disabling preserves its data. Uninstall only if you accept losing that app's local data. Leave apps marked kept unchanged alone.").font(.caption) }
                }
                Section("Private by design") {
                    NavigationLink("Open-source licenses") { ScrollView { Text(Catalog.notices()).font(.caption).textSelection(.enabled).padding() }.navigationTitle("Licenses") }
                    Text("No analytics or account credentials. Your ADB identity stays in this phone's Keychain. Downloads go directly to the pinned publishers. This installer never reads TV app profiles or imports someone else's preferences.").font(.caption)
                }
            }.navigationTitle("TV Setup")
        }.onChange(of: scenePhase) { phase in
            if phase == .background && model.busy { model.disconnect() }
        }
    }
}
