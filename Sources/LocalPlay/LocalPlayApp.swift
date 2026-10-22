import SwiftUI
import AppKit
import LocalPlayCore

@main
struct LocalPlayApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).preferredColorScheme(.dark).frame(minWidth: 960, minHeight: 640)
                .task { await model.load() }
        }
        .defaultSize(width: 1160, height: 790)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

enum Page: String, CaseIterable, Identifiable {
    case library = "Library", setup = "Setup", diagnostics = "Diagnostics"
    var id: Self { self }
    var icon: String { switch self { case .library: return "square.grid.2x2"; case .setup: return "shippingbox"; case .diagnostics: return "waveform.path.ecg" } }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page? = .setup
    @State private var stopConfirmation = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "gamecontroller.fill").font(.title).foregroundStyle(.mint)
                    VStack(alignment: .leading) { Text("LocalPlay").font(.title2.bold()); Text("WINDOWS GAMES. ON YOUR MAC.").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary) }
                }.padding(.top, 24).padding(.horizontal, 18)
                List(Page.allCases, selection: $page) { item in Label(item.rawValue, systemImage: item.icon).tag(item).padding(.vertical, 5) }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 9) {
                    Label("LOCAL EXECUTION", systemImage: "desktopcomputer").font(.caption2.bold()).foregroundStyle(.mint)
                    Text(model.hardware?.gpu ?? "Detecting hardware…").font(.callout.bold())
                    Text(model.hardware.map { "\($0.memoryGB) GB memory · \($0.freeGB) GB free" } ?? "Checking this Mac").font(.caption).foregroundStyle(.secondary)
                    Text("Early development build · 0.1").font(.caption2).foregroundStyle(.tertiary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Label(model.state.completed.contains(.graphics) ? "Runtime configured · gameplay unverified" : "Setup required", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(model.state.completed.contains(.graphics) ? .mint : .orange)
                    Spacer()
                    Button("Open Steam", systemImage: "arrow.up.forward.app") { model.launchSteam() }.disabled(model.busy)
                    Menu {
                        Button("Refresh library") { Task { await model.refresh() } }
                        Button("Reveal app data") { NSWorkspace.shared.open(model.paths.root) }
                        Button("Stop Windows environment…", role: .destructive) { stopConfirmation = true }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                }.padding(20).background(.background.secondary)
                Group {
                    switch page ?? .setup { case .setup: SetupView(); case .library: LibraryView(); case .diagnostics: DiagnosticsView() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Image(systemName: model.busy ? "arrow.down.circle" : "info.circle").foregroundStyle(.mint)
                    Text(model.message).font(.caption).textSelection(.enabled)
                    Spacer()
                }.padding(14).background(.background.secondary)
            }
        }
        .alert("Action needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Stop LocalPlay’s Windows environment?", isPresented: $stopConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Stop environment", role: .destructive) { model.stop() }
        } message: { Text("This closes Steam and all Windows games running inside LocalPlay. Save your game first.") }
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your games. Your Mac.").font(.system(size: 34, weight: .bold))
                    Text("Set up Windows Steam, sign in, and install a supported game. Everything runs locally.").foregroundStyle(.secondary).font(.title3)
                }
                HStack(spacing: 14) {
                    StatCard(title: "COMPATIBILITY", value: "WineCX 24.0.7", caption: "32-bit + 64-bit Windows")
                    StatCard(title: "GRAPHICS", value: "DXMT 0.80", caption: "DirectX 10 / 11 → Metal")
                    StatCard(title: "FIRST TARGET", value: "GTA V Legacy", caption: "Story Mode · unverified")
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Environment setup", systemImage: "shippingbox.fill").font(.headline)
                        Spacer()
                        Text("\(model.state.completed.count) / \(SetupStep.allCases.count)").foregroundStyle(.secondary).font(.caption.monospacedDigit())
                    }
                    ForEach(SetupStep.allCases, id: \.self) { step in
                        HStack(spacing: 12) {
                            Image(systemName: model.state.completed.contains(step) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.state.completed.contains(step) ? .mint : .secondary)
                            Text(step.title)
                            Spacer()
                            if model.busy, model.progress?.step == step { ProgressView().controlSize(.small) }
                        }.padding(.vertical, 4)
                    }
                    if model.busy { ProgressView(value: model.progress?.fraction ?? 0).tint(.mint) }
                    HStack {
                        Button(model.busy ? "Setting up…" : (model.state.completed.isEmpty ? "Set up LocalPlay" : "Continue / verify setup"), systemImage: "arrow.down.circle.fill") { model.setup() }
                            .buttonStyle(.borderedProminent).tint(.mint).controlSize(.large).disabled(model.busy)
                        Text("Game downloads start only when you choose them in Steam.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.padding(22).background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                if let failure = model.state.lastFailure {
                    Label(failure, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                }
                Label(model.hardware?.rosettaAvailable == true ? "Rosetta is available on this Mac." : "Rosetta is required; setup will check before running Wine.", systemImage: "cpu").font(.callout).foregroundStyle(.secondary)
                Text("This version has not yet been validated for gameplay on macOS 27. Setup runs real Windows execution tests; successful installation alone does not establish game compatibility.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Advanced · imports and troubleshooting") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.hardware?.macOS ?? "Detecting macOS…").font(.caption)
                        HStack { Button("Import Wine archive…") { model.chooseArchive(wine: true) }; Text(model.wineImport?.lastPathComponent ?? "Automatic download").font(.caption).foregroundStyle(.secondary) }
                        HStack { Button("Import DXMT archive…") { model.chooseArchive(wine: false) }; Text(model.dxmtImport?.lastPathComponent ?? "Automatic download").font(.caption).foregroundStyle(.secondary) }
                        HStack { Button("Import GStreamer package…") { model.chooseMedia() }; Text(model.mediaImport?.lastPathComponent ?? "Automatic download").font(.caption).foregroundStyle(.secondary) }
                        Button("Test Windows Notepad") { model.testNotepad() }
                        Text("Setup downloads the official GStreamer package, verifies its signature, and extracts media support into LocalPlay. This app-managed relocation still needs runtime validation. Approve macOS security prompts through System Settings. LocalPlay does not change Gatekeeper.").font(.caption).foregroundStyle(.secondary)
                        Link("Wine release and checksum", destination: URL(string: "https://github.com/Sikarugir-App/Engines/releases/tag/v1.0")!)
                        Link("DXMT release", destination: URL(string: "https://github.com/3Shain/dxmt/releases/tag/v0.80")!)
                    }.padding(.top, 12)
                }.disabled(model.busy)
            }.padding(30).frame(maxWidth: 1000, alignment: .leading)
        }
    }
}

struct StatCard: View {
    var title: String; var value: String; var caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
