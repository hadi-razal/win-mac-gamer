import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LocalPlayCore

@MainActor
final class AppModel: ObservableObject {
    let paths: Paths
    @Published var state = AppState()
    @Published var hardware: Hardware?
    @Published var games: [SteamGame] = []
    @Published var warnings: [String] = []
    @Published var busy = false
    @Published var progress: SetupProgress?
    @Published var message = "Ready to set up your local Windows environment."
    @Published var error: String?
    @Published var wineImport: URL?
    @Published var dxmtImport: URL?
    @Published var mediaImport: URL?
    @Published var logText = "Select Refresh logs to view the most recent runtime output."
    @Published var logFiles: [URL] = []
    private var processes: [Process] = []
    private var stateReadable = true
    init() {
        let root = ProcessInfo.processInfo.environment["LOCALPLAY_DATA_ROOT"].map { URL(fileURLWithPath: $0) }
        paths = Paths(root: root)
    }
    func load() async {
        do { try paths.prepare(); state = try StateStore(url: paths.state).load() }
        catch { stateReadable = false; self.error = "Settings could not be read. Keep settings.json as a backup before repairing it. \(error.localizedDescription)" }
        hardware = await Hardware.detect(at: paths.root)
        await refresh()
    }
    func refresh() async {
        let paths = paths; let extra = state.extraLibraries
        let result = await Task.detached { SteamLibrary.discover(paths: paths, extra: extra) }.value
        games = result.games; warnings = result.warnings
        processes.removeAll { !$0.isRunning }
    }
    func save() {
        guard stateReadable else { return }
        do { try StateStore(url: paths.state).save(state) } catch { self.error = error.localizedDescription }
    }
    func setup() {
        guard !busy, stateReadable else { return }; busy = true; error = nil
        Task {
            do {
                state = try await SetupManager(paths: paths).setup(wineImport: wineImport, dxmtImport: dxmtImport, mediaImport: mediaImport) { update in
                    Task { @MainActor in
                        self.progress = update; self.message = update.detail
                        if update.completed { self.state.finish(update.step) }
                    }
                }
                message = "Complete the Steam installer, then sign in through Steam. Use Open Steam after installation."
            } catch {
                self.error = error.localizedDescription
                if let saved = try? StateStore(url: paths.state).load() { state = saved }
            }
            busy = false; await refresh()
        }
    }
    func launchSteam(_ game: SteamGame? = nil) {
        do {
            guard state.completed.contains(.smoke32), state.completed.contains(.graphics) else { throw LocalPlayError.message("Complete runtime setup and both Windows execution tests first.") }
            let runtime = try WineRuntime(paths: paths)
            let settings = game.flatMap { state.games[$0.id] } ?? GameSettings()
            let process = try ProcessRunner.start(try runtime.steamCommand(appID: game?.id, settings: settings), log: newLog(game == nil ? "steam" : "launch-\(game!.id)"))
            processes.append(process)
            message = game.map { "Launch requested: \($0.name). Gameplay has not been confirmed." } ?? "Steam launch requested. Sign in inside the Windows Steam client."
        } catch { self.error = error.localizedDescription }
    }
    func installGTA() {
        do {
            guard state.completed.contains(.graphics), FileManager.default.fileExists(atPath: paths.steam.path) else { throw LocalPlayError.message("Finish setup and the Steam installer first.") }
            let runtime = try WineRuntime(paths: paths)
            processes.append(try ProcessRunner.start(runtime.command([paths.steam.path, "steam://install/271590"], graphics: true), log: newLog("steam-install-request")))
            message = "GTA V Legacy installation page requested in Steam. Review the download size and start it there."
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        guard !busy else { return }; busy = true
        Task {
            do {
                let runtime = try WineRuntime(paths: paths)
                let result = try await ProcessRunner.run(runtime.stopCommand(), log: newLog("stop"), timeout: 30)
                guard result.status == 0 else { throw LocalPlayError.message("Could not stop the Windows environment. Close its apps normally in Steam.") }
                message = "LocalPlay’s Windows environment stopped."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func testNotepad() {
        do {
            let runtime = try WineRuntime(paths: paths)
            processes.append(try ProcessRunner.start(runtime.command(["notepad.exe"]), log: newLog("notepad")))
            message = "Windows Notepad launch requested. Confirm that its window opens."
        } catch { self.error = error.localizedDescription }
    }
    func chooseArchive(wine: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = wine ? "Choose the official WS12WineCX24.0.7_7.tar.xz archive. Its published SHA-256 will be verified." : "Choose the official DXMT 0.80 release archive. Local imports record a hash; authenticity is not independently verified."
        if panel.runModal() == .OK { if wine { wineImport = panel.url } else { dxmtImport = panel.url } }
    }
    func addLibrary() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose a Windows Steam library folder or its steamapps directory. Install and manage the library in Windows Steam first."
        if panel.runModal() == .OK, let path = panel.url?.path, !state.extraLibraries.contains(path) { state.extraLibraries.append(path); save(); Task { await refresh() } }
    }
    func chooseMedia() {
        let panel = NSOpenPanel(); panel.message = "Choose the official signed GStreamer 1.28.5 universal .pkg. Its payload is extracted into LocalPlay; installer scripts are not run."
        if panel.runModal() == .OK { mediaImport = panel.url }
    }
    func launch(_ standalone: Standalone) {
        do {
            guard state.completed.contains(.graphics) else { throw LocalPlayError.message("Complete setup first.") }
            guard FileManager.default.fileExists(atPath: standalone.executable), FileManager.default.fileExists(atPath: standalone.directory) else { throw LocalPlayError.message("The executable or working directory is missing.") }
            let runtime = try WineRuntime(paths: paths)
            processes.append(try ProcessRunner.start(runtime.command([standalone.executable] + standalone.arguments, graphics: true, gameID: standalone.id, directory: URL(fileURLWithPath: standalone.directory)), log: newLog("standalone")))
            message = "Launch requested: \(standalone.name). Compatibility unknown."
        } catch { self.error = error.localizedDescription }
    }
    func applyGTA(_ settings: GameSettings) {
        let panel = NSOpenPanel(); panel.message = "Quit GTA first. Choose its existing settings.xml inside LocalPlay’s Windows environment. A backup is created before editing."
        panel.directoryURL = paths.prefix.appendingPathComponent("drive_c/users")
        if panel.runModal() == .OK, let file = panel.url {
            do {
                _ = try GTAConfiguration.apply(settings, to: file, prefix: paths.prefix)
                message = "GTA graphics settings saved, with a backup beside settings.xml. Disable Advanced Graphics manually in GTA."
            } catch { self.error = error.localizedDescription }
        }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "LocalPlay-diagnostics.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Diagnostics.export(state: state, hardware: hardware, to: url); message = "Diagnostics exported. Account data and raw runtime logs are excluded." }
            catch { self.error = error.localizedDescription }
        }
    }
    func refreshLogs() {
        logFiles = ((try? FileManager.default.contentsOfDirectory(at: paths.logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        if let file = logFiles.first { logText = ProcessRunner.tail(file) }
        else { logText = "No runtime logs yet." }
    }
    func newLog(_ name: String) -> URL { paths.logs.appendingPathComponent("\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(name).log") }
}
