import Foundation

public struct SetupProgress: Sendable {
    public var step: SetupStep
    public var fraction: Double
    public var detail: String
    public var completed: Bool
    public init(_ step: SetupStep, _ fraction: Double, _ detail: String, completed: Bool = false) { self.step = step; self.fraction = fraction; self.detail = detail; self.completed = completed }
}

public actor SetupManager {
    public static let wineURL = URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz")!
    public static let wineSHA = "203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c"
    public static let steamURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    public let paths: Paths
    private var busy = false
    private let preflight: @Sendable (URL) async -> Hardware
    public init(paths: Paths) { self.paths = paths; self.preflight = { await Hardware.detect(at: $0) } }
    init(paths: Paths, preflight: @escaping @Sendable (URL) async -> Hardware) { self.paths = paths; self.preflight = preflight }

    public func setup(wineImport: URL? = nil, dxmtImport: URL? = nil, mediaImport: URL? = nil, progress: @escaping @Sendable (SetupProgress) -> Void) async throws -> AppState {
        guard !busy else { throw LocalPlayError.message("Setup is already running.") }; busy = true; defer { busy = false }
        try paths.prepare()
        let store = StateStore(url: paths.state)
        var state = try store.load()
        func finish(_ step: SetupStep) throws { state.finish(step); try store.save(state); progress(SetupProgress(step, 1, step.title + " completed", completed: true)) }
        do {
            let hardware = await preflight(paths.root)
            guard hardware.rosettaAvailable else { throw LocalPlayError.message("Rosetta is required. Install it using Apple’s normal macOS prompt, then retry. No system settings have been changed.") }
            guard hardware.freeGB > 0 else { throw LocalPlayError.message("Available storage could not be determined. Open the native app outside the development terminal and retry.") }
            guard hardware.freeGB >= 8 else { throw LocalPlayError.message("Keep at least 8 GB free for setup, plus the space Steam requires for your games.") }
            if (try? WineRuntime(paths: paths)) == nil {
                progress(SetupProgress(.runtime, 0, "Downloading the official Wine archive"))
                let archive = wineImport ?? paths.downloads.appendingPathComponent("WS12WineCX24.0.7_7.tar.xz")
                if !FileManager.default.fileExists(atPath: archive.path) {
                    _ = try await Downloader().download(Self.wineURL, to: archive) { fraction in progress(SetupProgress(.runtime, fraction, "Downloading Wine")) }
                }
                let digest = try await Task.detached { try Downloader.verify(archive, expected: Self.wineSHA) }.value
                let staging = paths.runtime.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: staging) }
                try await Archive.extract(archive, to: staging)
                guard WineRuntime.find(named: "wine64", under: staging, executable: true) != nil || WineRuntime.find(named: "wine", under: staging, executable: true) != nil,
                      WineRuntime.find(named: "wineserver", under: staging, executable: true) != nil else {
                    throw LocalPlayError.message("The archive does not contain a macOS Wine runtime.")
                }
                // No replacement of an installed runtime: version combinations own distinct directories.
                guard !FileManager.default.fileExists(atPath: paths.runtime.path) else { throw LocalPlayError.message("An incomplete runtime directory exists. Reveal app data and rename Runtime/winecx-24.0.7_7-dxmt-0.80 to keep it as a backup, then retry.") }
                try FileManager.default.moveItem(at: staging, to: paths.runtime)
                state.archiveDigests["winecx-24.0.7_7"] = digest
            }
            let runtime = try WineRuntime(paths: paths)
            if !state.completed.contains(.media), WineRuntime.find(named: "libgstreamer-1.0.0.dylib", under: paths.runtime) == nil {
                progress(SetupProgress(.media, 0, "Preparing app-managed GStreamer 1.28.5"))
                let pkg = mediaImport ?? paths.downloads.appendingPathComponent("gstreamer-1.0-1.28.5-universal.pkg")
                if !FileManager.default.fileExists(atPath: pkg.path) {
                    let source = URL(string: "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.5/gstreamer-1.0-1.28.5-universal.pkg")!
                    _ = try await Downloader().download(source, to: pkg) { fraction in progress(SetupProgress(.media, fraction, "Downloading GStreamer media support")) }
                }
                try await installMedia(pkg)
                state.archiveDigests["gstreamer-1.28.5"] = try Downloader.sha256(pkg)
                try finish(.media)
            } else if !state.completed.contains(.media) {
                try finish(.media)
            }
            let version = try await ProcessRunner.run(runtime.command(["--version"]), log: paths.logs.appendingPathComponent("runtime-version.log"), timeout: 30)
            guard version.status == 0, version.output.contains("wine-") else {
                throw LocalPlayError.message("Wine could not start. Check Privacy & Security for a macOS approval prompt, then retry. Runtime log: \(version.output.suffix(1000))")
            }
            state.runtimeVersion = version.output.trimmingCharacters(in: .whitespacesAndNewlines)
            try finish(.runtime)

            if !state.completed.contains(.environment) || !FileManager.default.fileExists(atPath: paths.prefix.appendingPathComponent("system.reg").path) {
                progress(SetupProgress(.environment, 0, "Initializing LocalPlay’s dedicated environment"))
                let result = try await ProcessRunner.run(runtime.command(["wineboot", "-u"]), log: paths.logs.appendingPathComponent("wineboot.log"), timeout: 180)
                guard result.status == 0, FileManager.default.fileExists(atPath: paths.prefix.appendingPathComponent("system.reg").path) else {
                    throw LocalPlayError.message("Windows environment initialization failed. Check wineboot.log; existing game files were kept.")
                }
                try isolateUserFolders()
                try finish(.environment)
            }
            for (step, executable, marker) in [(SetupStep.smoke64, "C:\\windows\\system32\\cmd.exe", "LOCALPLAY_64_OK"), (.smoke32, "C:\\windows\\syswow64\\cmd.exe", "LOCALPLAY_32_OK")] {
                progress(SetupProgress(step, 0, "Testing Windows execution"))
                let result = try await ProcessRunner.run(runtime.command([executable, "/c", "echo", marker]), log: paths.logs.appendingPathComponent(step.rawValue + ".log"), timeout: 60)
                guard result.status == 0, result.output.contains(marker) else { throw LocalPlayError.message("\(step.title) failed. Inspect \(step.rawValue).log before installing games.") }
                try finish(step)
            }
            if !state.completed.contains(.graphics) {
                progress(SetupProgress(.graphics, 0, "Resolving official DXMT 0.80 release asset"))
                let archive: URL; var expected: String?
                if let dxmtImport { archive = dxmtImport }
                else {
                    let asset = try await dxmtAsset()
                    archive = paths.downloads.appendingPathComponent(asset.name)
                    expected = asset.digest?.replacingOccurrences(of: "sha256:", with: "")
                    if !FileManager.default.fileExists(atPath: archive.path) {
                        _ = try await Downloader().download(asset.browser_download_url, to: archive) { fraction in progress(SetupProgress(.graphics, fraction, "Downloading DXMT")) }
                    }
                }
                let digest = try await Task.detached { try Downloader.sha256(archive) }.value
                if let expected, digest != expected { throw LocalPlayError.message("DXMT checksum mismatch. Remove the cached DXMT archive and retry.") }
                try await installDXMT(archive, runtime: runtime)
                state.archiveDigests["dxmt-0.80"] = digest
                state.graphicsVersion = "DXMT 0.80 · installed, rendering unverified"
                try finish(.graphics)
            }
            let steamInstaller = paths.downloads.appendingPathComponent("SteamSetup.exe")
            if !FileManager.default.fileExists(atPath: paths.steam.path) {
                progress(SetupProgress(.steamDownload, 0, "Downloading Valve’s Windows Steam installer"))
                if !FileManager.default.fileExists(atPath: steamInstaller.path) {
                    _ = try await Downloader().download(Self.steamURL, to: steamInstaller) { fraction in progress(SetupProgress(.steamDownload, fraction, "Downloading Steam")) }
                }
                let header = try FileHandle(forReadingFrom: steamInstaller)
                let magic = try header.read(upToCount: 2); try header.close()
                guard magic == Data([0x4d, 0x5a]) else { throw LocalPlayError.message("Steam download is not a Windows executable. Delete Downloads/SteamSetup.exe in app data and retry.") }
                try finish(.steamDownload)
                _ = try ProcessRunner.start(runtime.command([steamInstaller.path]), log: uniqueLog("steam-installer"))
            } else {
                _ = try ProcessRunner.start(try runtime.steamCommand(), log: uniqueLog("steam"))
            }
            try finish(.steamInstaller)
            return state
        } catch {
            state.failed(error.localizedDescription); try store.save(state); throw error
        }
    }

    private struct Release: Decodable { var tag_name: String; var assets: [Asset] }
    private struct Asset: Decodable { var name: String; var browser_download_url: URL; var digest: String? }
    private func dxmtAsset() async throws -> Asset {
        let url = URL(string: "https://api.github.com/repos/3Shain/dxmt/releases/tags/v0.80")!
        var request = URLRequest(url: url); request.setValue("LocalPlay/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LocalPlayError.message("Could not read the upstream DXMT release. Retry, or import DXMT 0.80 from its release page.") }
        let release = try JSONDecoder().decode(Release.self, from: data)
        let assets = release.assets.filter { ($0.name.hasSuffix(".tar.gz") || $0.name.hasSuffix(".tar.xz")) && $0.name.lowercased().contains("dxmt") }
        guard release.tag_name == "v0.80", assets.count == 1, let asset = assets.first,
              asset.browser_download_url.host == "github.com", asset.browser_download_url.path.hasPrefix("/3Shain/dxmt/releases/download/v0.80/") else {
            throw LocalPlayError.message("DXMT release layout changed. Import the official DXMT 0.80 archive manually.")
        }
        return asset
    }

    private func installMedia(_ pkg: URL) async throws {
        let framework = paths.root.appendingPathComponent("Frameworks/GStreamer.framework")
        if FileManager.default.fileExists(atPath: framework.path) { return }
        let signature = try await ProcessRunner.run(Command("/usr/sbin/pkgutil", ["--check-signature", pkg.path]))
        guard signature.status == 0, signature.output.contains("signed by a certificate trusted") else {
            throw LocalPlayError.message("GStreamer package signature could not be validated. Obtain the official signed 1.28.5 package; no security checks were disabled.")
        }
        let staging = paths.root.appendingPathComponent("gstreamer-staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let result = try await ProcessRunner.run(Command("/usr/sbin/pkgutil", ["--expand-full", pkg.path, staging.path]), timeout: 300)
        guard result.status == 0, let source = WineRuntime.find(named: "GStreamer.framework", under: staging) else {
            throw LocalPlayError.message("GStreamer package layout changed. Media setup stopped; system frameworks were not modified.")
        }
        try FileManager.default.createDirectory(at: framework.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: framework)
    }

    private func installDXMT(_ archive: URL, runtime: WineRuntime) async throws {
        let staging = paths.root.appendingPathComponent("dxmt-staging-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try await Archive.extract(archive, to: staging)
        guard let unixSource = WineRuntime.find(named: "winemetal.so", under: staging),
              let unixTarget = WineRuntime.find(named: "winemac.so", under: paths.runtime)?.deletingLastPathComponent() else {
            throw LocalPlayError.message("DXMT archive layout is not supported, or Wine’s macOS driver is missing. No graphics backend has been enabled.")
        }
        // Runtime API visibility is a documented DXMT requirement.
        let symbols = try await ProcessRunner.run(Command("/usr/bin/nm", ["-gU", unixTarget.appendingPathComponent("winemac.so").path]))
        guard symbols.status == 0, symbols.output.contains("macdrv_create_metal_device"), symbols.output.contains("macdrv_get_client_cocoa_view") else {
            throw LocalPlayError.message("This Wine build does not expose the macOS APIs required by DXMT. Graphics setup stopped. A compatible upstream build is needed; WineD3D has not been silently substituted.")
        }
        let system32 = paths.prefix.appendingPathComponent("drive_c/windows/system32")
        let windowsRuntime = unixTarget.deletingLastPathComponent().appendingPathComponent("x86_64-windows")
        let names = ["winemetal.dll", "d3d11.dll", "dxgi.dll", "d3d10core.dll"]
        var sources: [(URL, URL)] = [(unixSource, unixTarget.appendingPathComponent("winemetal.so"))]
        for name in names {
            // Official release native DLL layout: x64, never substitute x32 for a 64-bit game.
            guard let files = FileManager.default.enumerator(at: staging, includingPropertiesForKeys: nil) else { continue }
            let candidates = files.compactMap { $0 as? URL }.filter { $0.lastPathComponent == name && !$0.path.contains("/x32/") && !$0.path.contains("/x86/") && !$0.path.contains("/i386-") }
            guard candidates.count == 1, let source = candidates.first else { throw LocalPlayError.message("Missing or ambiguous 64-bit DXMT \(name). Import the official release archive.") }
            sources.append((source, system32.appendingPathComponent(name)))
            if name == "winemetal.dll" { sources.append((source, windowsRuntime.appendingPathComponent(name))) }
        }
        // Stop only this prefix before replacing DLLs; preserve original components for rollback.
        _ = try await ProcessRunner.run(runtime.stopCommand(), timeout: 30)
        let backup = paths.root.appendingPathComponent("Backups/dxmt-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        var changed: [(URL, URL?)] = []
        do {
            for (source, target) in sources {
                let fm = FileManager.default
                let saved = fm.fileExists(atPath: target.path) ? backup.appendingPathComponent(UUID().uuidString + "-" + target.lastPathComponent) : nil
                if let saved { try fm.copyItem(at: target, to: saved); try fm.removeItem(at: target) }
                changed.append((target, saved))
                try fm.copyItem(at: source, to: target)
            }
        } catch {
            for (target, saved) in changed.reversed() {
                try? FileManager.default.removeItem(at: target)
                if let saved { try? FileManager.default.copyItem(at: saved, to: target) }
            }
            throw error
        }
    }

    private func isolateUserFolders() throws {
        let users = paths.prefix.appendingPathComponent("drive_c/users")
        for user in (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            for name in ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos", "My Documents"] {
                let path = user.appendingPathComponent(name)
                if (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    try FileManager.default.removeItem(at: path)
                    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                }
            }
        }
    }
    private func uniqueLog(_ name: String) -> URL { paths.logs.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).log") }
}
