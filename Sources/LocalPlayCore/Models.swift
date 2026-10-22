import Foundation
import Metal

public enum LocalPlayError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct Paths: Sendable {
    public let root: URL
    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalPlay")
    }
    public var runtime: URL { root.appendingPathComponent("Runtime/winecx-24.0.7_7-dxmt-0.80") }
    public var prefix: URL { root.appendingPathComponent("Environments/Steam-winecx-24.0.7_7-dxmt-0.80") }
    public var downloads: URL { root.appendingPathComponent("Downloads") }
    public var logs: URL { root.appendingPathComponent("Logs") }
    public var state: URL { root.appendingPathComponent("settings.json") }
    public var steam: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe") }
    public var steamFolder: URL { steam.deletingLastPathComponent() }
    public func prepare() throws {
        for dir in [root, downloads, logs, prefix.deletingLastPathComponent(), runtime.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

public struct Hardware: Codable, Sendable {
    public var macOS: String
    public var gpu: String
    public var memoryGB: Int
    public var freeGB: Int
    public var rosettaAvailable: Bool
    public static func detect(at root: URL) async -> Hardware {
        let translated = try? await ProcessRunner.run(Command("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]), timeout: 15)
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let fileSystem = try? FileManager.default.attributesOfFileSystem(forPath: root.path)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? (fileSystem?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        return Hardware(macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                        gpu: MTLCreateSystemDefaultDevice()?.name ?? "Metal GPU unavailable",
                        memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
                        freeGB: Int(free / 1_073_741_824),
                        rosettaAvailable: translated?.status == 0)
    }
}

public enum SetupStep: String, Codable, CaseIterable, Sendable {
    case runtime, media, environment, smoke64, smoke32, graphics, steamDownload, steamInstaller
    public var title: String {
        switch self {
        case .runtime: return "Install WineCX 24.0.7"
        case .media: return "Prepare GStreamer media support"
        case .environment: return "Create Windows environment"
        case .smoke64: return "Verify 64-bit Windows execution"
        case .smoke32: return "Verify 32-bit Windows execution"
        case .graphics: return "Install DXMT 0.80"
        case .steamDownload: return "Download Windows Steam"
        case .steamInstaller: return "Open Steam installer"
        }
    }
}

public struct Standalone: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var executable: String
    public var directory: String
    public var arguments: [String]
    public init(name: String, executable: String, directory: String, arguments: [String] = []) {
        self.id = UUID().uuidString; self.name = name; self.executable = executable; self.directory = directory; self.arguments = arguments
    }
}

public enum Preset: String, Codable, CaseIterable, Sendable { case balanced = "Balanced", performance = "Performance", custom = "Custom" }
public struct GameSettings: Codable, Equatable, Sendable {
    public var preset: Preset = .balanced
    public var width = 1440
    public var height = 900
    public var metalHUD = false
    public init() {}
    public mutating func select(_ preset: Preset) {
        self.preset = preset
        if preset == .balanced…926 tokens truncated…s, command, handle)
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
