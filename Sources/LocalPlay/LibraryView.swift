import SwiftUI
import AppKit
import LocalPlayCore

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var selected: String?
    @State private var addExecutable = false
    var filtered: [SteamGame] { model.games.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("Game library").font(.largeTitle.bold()); Text("Discovered from your Windows Steam installation.").foregroundStyle(.secondary) }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.keyboardShortcut("r")
                Menu("Add", systemImage: "plus") {
                    Button("Steam library folder…") { model.addLibrary() }
                    Button("Standalone Windows executable…") { addExecutable = true }
                }
            }
            TextField("Search installed games", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel("Search installed games")
            if model.games.isEmpty && model.state.standalone.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller").font(.system(size: 52)).foregroundStyle(.mint)
                    Text("Make room for play.").font(.title.bold())
                    Text("Finish setup, sign in through Windows Steam, then install a game. Your installed games will appear here after Refresh.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                    Button("Find GTA V Legacy in Steam", systemImage: "arrow.up.forward.app") { model.installGTA() }.buttonStyle(.borderedProminent).tint(.mint)
                    Text("Not installed · Story Mode target · GTA Online unsupported").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { game in
                                Button { selected = game.id } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "gamecontroller.fill").font(.title2).foregroundStyle(.mint).frame(width: 50, height: 54).background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 5) { Text(game.name).font(.headline); Text(game.state).font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }.padding(12).background(selected == game.id ? .mint.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                            if !model.state.standalone.isEmpty {
                                Text("STANDALONE").font(.caption2.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                                ForEach(model.state.standalone) { game in
                                    HStack {
                                        VStack(alignment: .leading) { Text(game.name); Text("Compatibility unknown").font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Button("Launch") { model.launch(game) }
                                        Button { model.state.standalone.removeAll { $0.id == game.id }; model.save() } label: { Image(systemName: "minus.circle") }.help("Remove shortcut; game files are kept")
                                    }.padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    if let game = model.games.first(where: { $0.id == selected }) {
                        GameDetail(game: game).id(game.id).frame(width: 310)
                    }
                }
            }
            if !model.warnings.isEmpty {
                DisclosureGroup("\(model.warnings.count) library notice(s)") { ForEach(model.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
            }
            if !model.state.extraLibraries.isEmpty {
                DisclosureGroup("Additional library locations") {
                    ForEach(model.state.extraLibraries, id: \.self) { path in
                        HStack {
                            Text(path).font(.caption).textSelection(.enabled); Spacer()
                            Button("Remove shortcut") { model.state.extraLibraries.removeAll { $0 == path }; model.save(); Task { await model.refresh() } }
                        }
                    }
                }
            }
        }.padding(28).disabled(model.busy).sheet(isPresented: $addExecutable) { AddExecutableView() }
    }
}

struct GameDetail: View {
    @EnvironmentObject var model: AppModel
    var game: SteamGame
    @State private var settings = GameSettings()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(game.name).font(.title2.bold())
                Text(game.compatibility).font(.callout).foregroundStyle(.secondary)
                Text("Steam app \(game.id) · build \(game.buildID)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button("Launch through Steam", systemImage: "play.fill") { model.launchSteam(game) }.buttonStyle(.borderedProminent).tint(.mint).controlSize(.large).disabled(!game.launchable)
                Text("Launch requested does not mean the game is running. Confirm the game window and gameplay yourself.").font(.caption).foregroundStyle(.secondary)
                Button("Reveal game files", systemImage: "folder") { NSWorkspace.shared.open(game.installDirectory) }
                Divider()
                Text("Performance settings").font(.headline)
                Picker("Preset", selection: $settings.preset) { ForEach(Preset.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .onChange(of: settings.preset) { _, value in settings.select(value); persist() }
                HStack { TextField("Width", value: $settings.width, format: .number.grouping(.never)); Text("×"); TextField("Height", value: $settings.height, format: .number.grouping(.never)) }.textFieldStyle(.roundedBorder)
                Toggle("Metal performance HUD", isOn: $settings.metalHUD)
                Text("The HUD is requested through Apple’s Metal environment setting. Fully quit Windows Steam before launching for changed environment options to take effect. FPS collection in LocalPlay is unavailable.").font(.caption).foregroundStyle(.secondary)
                Button("Save settings") { persist() }
                if game.id == "271590" {
                    Button("Apply to GTA settings.xml…") { model.applyGTA(settings) }
                    Text("Run Story Mode once to create settings.xml, then quit GTA before applying. Resolution, moderate textures, shadows/reflections, and disabled MSAA are starting candidates. Turn Advanced Graphics off inside GTA. Try a sustained 30 FPS target and benchmark for 15–20 minutes.").font(.caption).foregroundStyle(.secondary)
                    Text("For Story Mode, disable BattlEye using Rockstar Launcher’s Settings control. GTA Online is unsupported.").font(.caption).foregroundStyle(.orange)
                    Link("Rockstar’s BattlEye guidance", destination: URL(string: "https://support.rockstargames.com/articles/1nenwhZlVrJY6CTFeSS2Fx/grand-theft-auto-online-battleye-faq")!)
                } else {
                    Text("Resolution presets are saved as a reference. Configure this game’s graphics inside the game; LocalPlay does not invent launch flags.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18).background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }.onAppear { settings = model.state.games[game.id] ?? GameSettings() }
    }
    func persist() { model.state.games[game.id] = settings; model.save() }
}

struct AddExecutableView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var executable = ""
    @State private var directory = ""
    @State private var arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Windows program").font(.title2.bold())
            TextField("Name", text: $name)
            HStack { Text(executable.isEmpty ? "Choose a legitimate .exe file" : executable).font(.caption).lineLimit(2); Spacer(); Button("Choose executable…") { choose(false) } }
            HStack { Text(directory.isEmpty ? "Choose its working directory" : directory).font(.caption).lineLimit(2); Spacer(); Button("Working directory…") { choose(true) } }
            Text("Arguments · one argument per line, without shell quoting").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $arguments).font(.system(.body, design: .monospaced)).frame(height: 100)
            Text("This only creates a shortcut. Compatibility is unknown; the program runs with your account’s file access.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Add program") {
                model.state.standalone.append(Standalone(name: name, executable: executable, directory: directory, arguments: arguments.split(separator: "\n").map(String.init)))
                model.save(); dismiss()
            }.buttonStyle(.borderedProminent).disabled(name.isEmpty || executable.isEmpty || directory.isEmpty) }
        }.padding(24).frame(width: 560).textFieldStyle(.roundedBorder)
    }
    func choose(_ isDirectory: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = isDirectory; panel.canChooseFiles = !isDirectory
        if panel.runModal() == .OK, let url = panel.url {
            if isDirectory { directory = url.path }
            else {
                guard url.pathExtension.lowercased() == "exe" else { return }
                executable = url.path; if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                if directory.isEmpty { directory = url.deletingLastPathComponent().path }
            }
        }
    }
}
