import Foundation

public enum GTAConfiguration {
    // Only edits an existing game's XML. Never fabricates settings or changes a native installation.
    public static func apply(_ settings: GameSettings, to file: URL, prefix: URL) throws -> URL {
        let real = file.resolvingSymlinksInPath().standardizedFileURL
        guard real.path.hasPrefix(prefix.resolvingSymlinksInPath().path + "/"), file.lastPathComponent == "settings.xml" else {
            throw LocalPlayError.message("Choose GTA Legacy’s settings.xml inside LocalPlay’s Windows environment.")
        }
        guard (640...3840).contains(settings.width), (480...2160).contains(settings.height) else { throw LocalPlayError.message("Resolution is outside the supported range.") }
        let document = try XMLDocument(contentsOf: file, options: [.nodePreserveAll])
        guard document.rootElement()?.name == "Settings" else { throw LocalPlayError.message("This is not a recognized GTA settings file.") }
        let changes = ["/Settings/video/ScreenWidth": settings.width, "/Settings/video/ScreenHeight": settings.height,
                       "/Settings/graphics/MSAA": 0, "/Settings/graphics/ReflectionMSAA": 0,
                       "/Settings/graphics/ShadowQuality": 1, "/Settings/graphics/ReflectionQuality": 1,
                       "/Settings/graphics/TextureQuality": 1]
        var edits = 0
        for (path, value) in changes {
            if let node = try document.nodes(forXPath: path).first as? XMLElement, let attribute = node.attribute(forName: "value") {
                attribute.stringValue = String(value); edits += 1
            }
        }
        guard edits >= 2 else { throw LocalPlayError.message("Expected settings are missing. Set graphics in the game instead.") }
        let backup = file.deletingLastPathComponent().appendingPathComponent("settings.\(UUID().uuidString).backup.xml")
        try FileManager.default.copyItem(at: file, to: backup)
        try document.xmlData.write(to: file, options: .atomic)
        return backup
    }
}

public enum Diagnostics {
    public static func export(state: AppState, hardware: Hardware?, to url: URL) throws {
        // Strict allowlist: no raw runtime logs, arguments, library locations, account files or usernames.
        let report: [String: Any] = [
            "created": ISO8601DateFormatter().string(from: Date()),
            "appVersion": "0.1.0",
            "macOS": hardware?.macOS ?? "unavailable", "gpu": hardware?.gpu ?? "unavailable",
            "memoryGB": hardware?.memoryGB ?? 0, "freeGB": hardware?.freeGB ?? 0,
            "rosettaAvailable": hardware?.rosettaAvailable ?? false,
            "runtime": state.runtimeVersion ?? "not installed", "graphics": state.graphicsVersion ?? "not installed",
            "completedSteps": state.completed.map(\.rawValue).sorted(), "archiveSHA256": state.archiveDigests,
            "performance": ["averageFPS": "unavailable", "frameTime": "unavailable", "lows": "unavailable"],
            "gameplayVerified": false
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
