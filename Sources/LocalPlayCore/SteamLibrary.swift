import Foundation

public indirect enum VDF: Equatable, Sendable {
    case string(String), object([String: VDF])
    public subscript(_ key: String) -> VDF? { if case .object(let values) = self { return values[key] }; return nil }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var object: [String: VDF]? { if case .object(let value) = self { return value }; return nil }
}

public enum VDFParser {
    public static func parse(_ text: String) throws -> VDF {
        let chars = Array(text); var i = 0; var tokens: [String] = []
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i+1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }; continue
            }
            if c == "{" || c == "}" { tokens.append(String(c)); i += 1; continue }
            var token = ""
            if c == "\"" {
                i += 1; var closed = false
                while i < chars.count {
                    if chars[i] == "\"" { i += 1; closed = true; break }
                    if chars[i] == "\\", i + 1 < chars.count, chars[i+1] == "\\" || chars[i+1] == "\"" {
                        i += 1
                    }
                    token.append(chars[i]); i += 1
                }
                guard closed else { throw LocalPlayError.message("Unterminated Steam manifest string.") }
            } else {
                while i < chars.count && !chars[i].isWhitespace && chars[i] != "{" && chars[i] != "}" { token.append(chars[i]); i += 1 }
            }
            tokens.append(token)
        }
        var position = 0
        func object(_ nested: Bool) throws -> VDF {
            var values: [String: VDF] = [:]
            while position < tokens.count {
                let key = tokens[position]; position += 1
                if key == "}" {
                    guard nested else { throw LocalPlayError.message("Unexpected Steam manifest brace.") }; return .object(values)
                }
                guard key != "{", position < tokens.count else { throw LocalPlayError.message("Incomplete Steam manifest.") }
                let value = tokens[position]; position += 1
                if value == "{" { values[key] = try object(true) }
                else if value == "}" { throw LocalPlayError.message("Missing Steam manifest value.") }
                else { values[key] = .string(value) }
            }
            guard !nested else { throw LocalPlayError.message("Unclosed Steam manifest object.") }
            return .object(values)
        }
        return try object(false)
    }
}

public enum WindowsPath {
    public static func resolve(_ path: String, prefix: URL) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let chars = Array(normalized)
        guard chars.count >= 3, chars[1] == ":", chars[2] == "/", chars[0].isLetter else {
            throw LocalPlayError.message("Expected an absolute Windows drive path: \(path)")
        }
        let drive = String(chars[0]).lowercased()
        let parts = String(chars.dropFirst(3)).split(separator: "/").map(String.init)
        guard !parts.contains("..") else { throw LocalPlayError.message("Parent traversal in Windows path.") }
        let base: URL
        if drive == "c" { base = prefix.appendingPathComponent("drive_c") }
        else {
            let device = prefix.appendingPathComponent("dosdevices/\(drive):")
            guard FileManager.default.fileExists(atPath: device.path) else { throw LocalPlayError.message("Windows drive \(drive.uppercased()): is not mapped.") }
            base = device.resolvingSymlinksInPath()
        }
        return parts.reduce(base) { $0.appendingPathComponent($1) }.standardizedFileURL
    }
}

public struct SteamGame: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var installDirectory: URL
    public var buildID: String
    public var state: String
    public var launchable: Bool
    public var compatibility: String {
        switch id {
        case "271590": return "Legacy Story Mode · unverified on this Mac. GTA Online unsupported. Rockstar sign-in required."
        case "3240220": return "Enhanced · experimental. DirectX 12 is not provided by the selected DXMT backend."
        default: return "Compatibility unknown · DirectX 10/11 backend"
        }
    }
}

public enum SteamLibrary {
    public static func discover(paths: Paths, extra: [String]) -> (games: [SteamGame], warnings: [String]) {
        var libraries: [URL] = [paths.steamFolder]; var warnings: [String] = []
        let vdf = paths.steamFolder.appendingPathComponent("steamapps/libraryfolders.vdf")
        if FileManager.default.fileExists(atPath: vdf.path) {
            do {
                let folders = try VDFParser.parse(String(contentsOf: vdf, encoding: .utf8))["libraryfolders"]?.object ?? [:]
                for (key, value) in folders where Int(key) != nil {
                    if let path = value["path"]?.string ?? value.string {
                        do { libraries.append(try WindowsPath.resolve(path, prefix: paths.prefix)) }
                        catch { warnings.append(error.localizedDescription) }
                    }
                }
            } catch { warnings.append("libraryfolders.vdf: \(error.localizedDescription)") }
        }
        libraries += extra.map { URL(fileURLWithPath: $0) }
        var seen: Set<String> = []; var games: [SteamGame] = []
        for library in Set(libraries.map { $0.standardizedFileURL }) {
            let apps = library.lastPathComponent.lowercased() == "steamapps" ? library : library.appendingPathComponent("steamapps")
            guard let manifests = try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil) else { continue }
            for manifest in manifests.filter({ $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }).sorted(by: { $0.path < $1.path }) {
                do {
                    let app = try VDFParser.parse(String(contentsOf: manifest, encoding: .utf8))["AppState"]
                    guard let id = app?["appid"]?.string, id.allSatisfy(\.isNumber), !id.isEmpty,
                          let name = app?["name"]?.string, let dir = app?["installdir"]?.string,
                          !dir.contains("/"), !dir.contains("\\"), dir != "..", !dir.isEmpty else {
                        throw LocalPlayError.message("Invalid app ID or installation directory")
                    }
                    let install = apps.appendingPathComponent("common").appendingPathComponent(dir)
                    let flags = UInt64(app?["StateFlags"]?.string ?? "") ?? 0
                    let required = UInt64(app?["BytesToDownload"]?.string ?? "0") ?? 0
                    let downloaded = UInt64(app?["BytesDownloaded"]?.string ?? "0") ?? 0
                    let exists = FileManager.default.fileExists(atPath: install.path)
                    let complete = flags & 4 != 0 && flags & 2 == 0 && required <= downloaded && exists
                    let state = complete ? "Installed" : (required > downloaded ? "Downloading / update incomplete" : "Incomplete / update required")
                    let game = SteamGame(id: id, name: name, installDirectory: install, buildID: app?["buildid"]?.string ?? "unknown", state: state, launchable: complete && id != "3240220")
                    // Prefer a complete copy if multiple Steam libraries retain a manifest.
                    if seen.insert(id).inserted { games.append(game) }
                    else if game.launchable, let index = games.firstIndex(where: { $0.id == id && !$0.launchable }) { games[index] = game }
                } catch { warnings.append("\(manifest.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        return (games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, warnings)
    }
}
