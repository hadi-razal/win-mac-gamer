import Foundation

public struct Command: Sendable {
    public let executable: String
    public let arguments: [String]
    public var environment: [String: String]
    public var directory: URL?
    public init(_ executable: String, _ arguments: [String] = [], environment: [String: String] = [:], directory: URL? = nil) {
        self.executable = executable; self.arguments = arguments; self.environment = environment; self.directory = directory
    }
}
public struct ProcessResult: Sendable {
    public let status: Int32
    public let output: String
}

public enum ProcessRunner {
    // Disk redirection avoids pipe-buffer deadlocks. Only a bounded tail is loaded into memory.
    public static func run(_ command: Command, log: URL? = nil, timeout: TimeInterval = 120) async throws -> ProcessResult {
        try await Task.detached {
            let temporary = log == nil
            let target = log ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { if temporary { try? FileManager.default.removeItem(at: target) } }
            let process = Process()
            let handle = try makeLog(target)
            defer { try? handle.close() }
            configure(process, command, handle)
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Task.isCancelled || Date() > deadline {
                    process.terminate()
                    throw LocalPlayError.message("Process timed out or was cancelled. Its child environment may still be active; use Stop environment if needed.")
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            process.waitUntilExit()
            return ProcessResult(status: process.terminationStatus, output: tail(target))
        }.value
    }
    public static func start(_ command: Command, log: URL) throws -> Process {
        let process = Process(); let handle = try makeLog(log)
        configure(process, command, handle)
        process.terminationHandler = { _ in try? handle.close() }
        do { try process.run() } catch { try? handle.close(); throw error }
        return process
    }
    private static func configure(_ process: Process, _ command: Command, _ handle: FileHandle) {
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        // Do not inherit a different wrapper's Wine or graphics configuration.
        for key in environment.keys where key.hasPrefix("WINE") || key.hasPrefix("DXMT") || key.hasPrefix("DYLD_") || key.hasPrefix("DXVK") {
            environment.removeValue(forKey: key)
        }
        environment.merge(command.environment) { _, new in new }
        process.environment = environment; process.currentDirectoryURL = command.directory
        process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
    }
    private static func makeLog(_ url: URL) throws -> FileHandle {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        return try FileHandle(forWritingTo: url)
    }
    public static func tail(_ url: URL, maxBytes: UInt64 = 64 * 1024) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? file.close() }
        let end = (try? file.seekToEnd()) ?? 0
        try? file.seek(toOffset: end > maxBytes ? end - maxBytes : 0)
        return String(decoding: (try? file.readToEnd()) ?? Data(), as: UTF8.self)
    }
}

public struct WineRuntime: Sendable {
    public let wine: URL
    public let server: URL
    public let paths: Paths
    public init(paths: Paths) throws {
        self.paths = paths
        guard let wine = Self.find(named: "wine64", under: paths.runtime, executable: true) ?? Self.find(named: "wine", under: paths.runtime, executable: true),
              let server = Self.find(named: "wineserver", under: paths.runtime, executable: true) else {
            throw LocalPlayError.message("Wine is not installed. Run setup or import the pinned Wine archive.")
        }
        self.wine = wine; self.server = server
    }
    public static func find(named: String, under root: URL, executable: Bool = false) -> URL? {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in files where url.lastPathComponent == named {
            if executable && !fm.isExecutableFile(atPath: url.path) { continue }
            return url
        }
        return nil
    }
    public func command(_ arguments: [String], graphics: Bool = false, settings: GameSettings = .init(), gameID: String = "steam", directory: URL? = nil) -> Command {
        var env = ["WINEPREFIX": paths.prefix.path, "WINEDEBUG": "-all", "WINEARCH": "win64",
                   "DYLD_FALLBACK_FRAMEWORK_PATH": paths.root.appendingPathComponent("Frameworks").path,
                   "DYLD_FRAMEWORK_PATH": paths.root.appendingPathComponent("Frameworks").path]
        let media = paths.root.appendingPathComponent("Frameworks/GStreamer.framework/Versions/1.0")
        if FileManager.default.fileExists(atPath: media.path) {
            env["GST_PLUGIN_SYSTEM_PATH_1_0"] = media.appendingPathComponent("lib/gstreamer-1.0").path
            env["GST_PLUGIN_SCANNER"] = media.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner").path
        }
        if graphics {
            env["WINEDLLOVERRIDES"] = "dxgi,d3d11,d3d10core=n,b"
            env["DXMT_SHADER_CACHE_PATH"] = paths.root.appendingPathComponent("ShaderCaches/winecx-24.0.7_7-dxmt-0.80").path
            env["DXMT_LOG_PATH"] = paths.logs.path
            env["DXMT_LOG_LEVEL"] = "warn"
            if settings.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        }
        return Command(wine.path, arguments, environment: env, directory: directory)
    }
    public func steamCommand(appID: String? = nil, settings: GameSettings = .init()) throws -> Command {
        guard FileManager.default.fileExists(atPath: paths.steam.path) else {
            throw LocalPlayError.message("Finish Valve’s Windows Steam installer, then open Steam again.")
        }
        if let id = appID {
            guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw LocalPlayError.message("Invalid Steam app identifier.") }
            return command([paths.steam.path, "-applaunch", id], graphics: true, settings: settings, gameID: id, directory: paths.steamFolder)
        }
        return command([paths.steam.path], graphics: true, directory: paths.steamFolder)
    }
    public func stopCommand() -> Command {
        Command(server.path, ["-k"], environment: ["WINEPREFIX": paths.prefix.path])
    }
}
