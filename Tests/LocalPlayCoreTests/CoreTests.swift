import XCTest
@testable import LocalPlayCore

final class CoreTests: XCTestCase {
    func temporary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalPlayTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    func testManifestNestedUnicodeEscapesAndComments() throws {
        let data = #"""
        // Steam file
        "AppState" {
          "appid" "271590"
          "name" "GTA \"Legacy\" — കേരളം"
          "path" "Z:\\Volumes\\Game SSD\\SteamLibrary"
          "InstalledDepots" { "123" { "manifest" "999" } }
        }
        """#
        let parsed = try VDFParser.parse(data)
        XCTAssertEqual(parsed["AppState"]?["appid"]?.string, "271590")
        XCTAssertEqual(parsed["AppState"]?["name"]?.string, "GTA \"Legacy\" — കേരളം")
        XCTAssertEqual(parsed["AppState"]?["path"]?.string, "Z:\\Volumes\\Game SSD\\SteamLibrary")
        XCTAssertEqual(parsed["AppState"]?["InstalledDepots"]?["123"]?["manifest"]?.string, "999")
    }
    func testMalformedManifestRejected() {
        for text in ["\"AppState\" { \"appid\"", "\"AppState\" {", "}", "\"unterminated"] { XCTAssertThrowsError(try VDFParser.parse(text)) }
    }
    func testWindowsPathMappingSpacesUnicodeAndExternalDrive() throws {
        let root = try temporary()
        let prefix = root.appendingPathComponent("prefix")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: prefix.appendingPathComponent("dosdevices/z:").path, withDestinationPath: "/")
        let c = try WindowsPath.resolve("C:\\Program Files (x86)\\Steam\\കേരളം", prefix: prefix)
        XCTAssertEqual(c.path, prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/കേരളം").path)
        XCTAssertEqual(try WindowsPath.resolve("Z:\\Volumes\\Games SSD\\SteamLibrary", prefix: prefix).path, "/Volumes/Games SSD/SteamLibrary")
        XCTAssertThrowsError(try WindowsPath.resolve("C:\\..\\private", prefix: prefix))
        XCTAssertThrowsError(try WindowsPath.resolve("\\\\server\\share", prefix: prefix))
        XCTAssertThrowsError(try WindowsPath.resolve("D:\\Games", prefix: prefix))
    }
    func testDiscoveryUsesActualManifestsAndInstallationState() throws {
        let root = try temporary(); let paths = Paths(root: root)
        let steamapps = paths.steamFolder.appendingPathComponent("steamapps")
        try write(#"""
        "AppState" { "appid" "271590" "name" "Grand Theft Auto V Legacy" "installdir" "Grand Theft Auto V" "StateFlags" "4" "buildid" "12345" }
        """#, steamapps.appendingPathComponent("appmanifest_271590.acf"))
        var discovered = SteamLibrary.discover(paths: paths, extra: [])
        XCTAssertEqual(discovered.games.count, 1)
        XCTAssertFalse(discovered.games[0].launchable)
        try FileManager.default.createDirectory(at: steamapps.appendingPathComponent("common/Grand Theft Auto V"), withIntermediateDirectories: true)
        discovered = SteamLibrary.discover(paths: paths, extra: [])
        XCTAssertTrue(discovered.games[0].launchable)
        XCTAssertEqual(discovered.games[0].buildID, "12345")
        try write(#"""
        "AppState" { "appid" "271590" "name" "GTA" "installdir" "Grand Theft Auto V" "StateFlags" "6" "BytesToDownload" "999" "BytesDownloaded" "10" }
        """#, steamapps.appendingPathComponent("appmanifest_271590.acf"))
        discovered = SteamLibrary.discover(paths: paths, extra: [])
        XCTAssertFalse(discovered.games[0].launchable)
        XCTAssertTrue(discovered.games[0].state.contains("Downloading"))
    }
    func testAdditionalLibrariesAndUnsafeInstallPaths() throws {
        let root = try temporary(); let paths = Paths(root: root)
        let external = root.appendingPathComponent("External Library/steamapps")
        try write(#"""
        "AppState" { "appid" "42" "name" "Example" "installdir" "../escape" "StateFlags" "4" }
        """#, external.appendingPathComponent("appmanifest_42.acf"))
        let discovered = SteamLibrary.discover(paths: paths, extra: [external.path])
        XCTAssertTrue(discovered.games.isEmpty)
        XCTAssertEqual(discovered.warnings.count, 1)
    }
    func testSettingsRoundTripRetainsRecoveryCheckpoint() throws {
        let root = try temporary(); let store = StateStore(url: root.appendingPathComponent("settings.json"))
        var state = AppState(); state.finish(.runtime); state.finish(.environment)
        state.extraLibraries = ["/Volumes/Game SSD/കേരളം"]
        state.standalone = [Standalone(name: "Owned game", executable: "/games/game.exe", directory: "/games")]
        var setting = GameSettings(); setting.select(.performance); state.games["271590"] = setting
        state.failed("Network interrupted")
        try store.save(state)
        var restored = try store.load()
        XCTAssertEqual(restored.completed, [.runtime, .environment])
        XCTAssertEqual(restored.games["271590"], setting)
        XCTAssertEqual(restored.lastFailure, "Network interrupted")
        restored.finish(.smoke64); try store.save(restored)
        let retry = try store.load()
        XCTAssertNil(retry.lastFailure)
        XCTAssertEqual(retry.standalone.count, 1)
        XCTAssertEqual(retry.extraLibraries, state.extraLibraries)
    }
    func testCorruptSettingsAreNotSilentlyReset() throws {
        let file = try temporary().appendingPathComponent("settings.json")
        try write("{ broken", file)
        XCTAssertThrowsError(try StateStore(url: file).load())
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ broken")
    }
    func testArgumentsPassedLiterallyWithoutShellInterpretation() async throws {
        let root = try temporary(); let sentinel = root.appendingPathComponent("must-not-exist")
        let arg = "spaces കേരളം $(touch \(sentinel.path)) `touch \(sentinel.path)` ; echo injected"
        let result = try await ProcessRunner.run(Command("/usr/bin/printf", ["%s", arg]))
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, arg)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }
    func testVerboseProcessDoesNotDeadlock() async throws {
        let log = try temporary().appendingPathComponent("verbose.log")
        let result = try await ProcessRunner.run(Command("/usr/bin/awk", ["BEGIN { for(i=0;i<100000;i++) print \"log output\" }"]), log: log, timeout: 15)
        XCTAssertEqual(result.status, 0)
        XCTAssertLessThanOrEqual(result.output.utf8.count, 65536)
        XCTAssertGreaterThan(try Data(contentsOf: log).count, 1_000_000)
    }
    func testStopIsScopedToOwnedPrefix() throws {
        let paths = Paths(root: try temporary())
        try write("#!/bin/sh\nexit 0\n", paths.runtime.appendingPathComponent("bin/wine"))
        try write("#!/bin/sh\nexit 0\n", paths.runtime.appendingPathComponent("bin/wineserver"))
        for name in ["wine", "wineserver"] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.runtime.appendingPathComponent("bin/\(name)").path) }
        let runtime = try WineRuntime(paths: paths)
        XCTAssertEqual(runtime.stopCommand().environment["WINEPREFIX"], paths.prefix.path)
        XCTAssertEqual(runtime.stopCommand().arguments, ["-k"])
        try write("placeholder", paths.steam)
        XCTAssertEqual(try runtime.steamCommand(appID: "271590").arguments, [paths.steam.path, "-applaunch", "271590"])
        XCTAssertThrowsError(try runtime.steamCommand(appID: "42; rm"))
    }
    func testSetupFailureRetainsCheckpointAndExistingGameData() async throws {
        let paths = Paths(root: try temporary()); try paths.prepare()
        let fakeWine = "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo wine-9.0; exit 0; fi\necho Intentional bootstrap failure; exit 7\n"
        try write(fakeWine, paths.runtime.appendingPathComponent("bin/wine"))
        try write("#!/bin/sh\nexit 0\n", paths.runtime.appendingPathComponent("bin/wineserver"))
        for name in ["wine", "wineserver"] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.runtime.appendingPathComponent("bin/\(name)").path) }
        let game = paths.prefix.appendingPathComponent("drive_c/game/save.dat"); try write("existing-save", game)
        var original = AppState(); original.games["271590"] = GameSettings(); original.finish(.media)
        try StateStore(url: paths.state).save(original)
        do {
            let setup = SetupManager(paths: paths, preflight: { _ in Hardware(macOS: "test", gpu: "test", memoryGB: 16, freeGB: 100, rosettaAvailable: true) })
            _ = try await setup.setup(progress: { _ in })
            XCTFail("Expected bootstrap failure")
        } catch {
            let recovered = try StateStore(url: paths.state).load()
            XCTAssertTrue(recovered.completed.contains(.runtime))
            XCTAssertFalse(recovered.completed.contains(.environment))
            XCTAssertNotNil(recovered.lastFailure)
            XCTAssertEqual(recovered.games["271590"], original.games["271590"])
            XCTAssertEqual(try String(contentsOf: game, encoding: .utf8), "existing-save")
        }
    }
    func testSHA256VerificationAndArchiveTraversal() throws {
        let file = try temporary().appendingPathComponent("archive")
        try write("abc", file)
        XCTAssertEqual(try Downloader.verify(file, expected: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try Downloader.verify(file, expected: "wrong"))
        XCTAssertNoThrow(try Archive.validateEntries("./Wine Devel.app/Contents/bin/wine\n"))
        XCTAssertThrowsError(try Archive.validateEntries("../../escape"))
        XCTAssertThrowsError(try Archive.validateEntries("/absolute/path"))
    }
    func testGTAPresetBacksUpAndPreservesOtherSettings() throws {
        let root = try temporary(); let prefix = root.appendingPathComponent("prefix")
        let file = prefix.appendingPathComponent("drive_c/users/player/Documents/Rockstar Games/GTA V/settings.xml")
        let original = "<Settings><graphics><MSAA value=\"4\"/><TextureQuality value=\"2\"/><Other value=\"99\"/></graphics><video><ScreenWidth value=\"1920\"/><ScreenHeight value=\"1080\"/></video></Settings>"
        try write(original, file)
        var settings = GameSettings(); settings.select(.performance)
        let backup = try GTAConfiguration.apply(settings, to: file, prefix: prefix)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
        let output = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(output.contains("1280")); XCTAssertTrue(output.contains("99"))
        let outside = root.appendingPathComponent("outside/settings.xml"); try write(original, outside)
        XCTAssertThrowsError(try GTAConfiguration.apply(settings, to: outside, prefix: prefix))
    }
    func testDiagnosticsExportExcludesSensitiveStateAndPaths() throws {
        let file = try temporary().appendingPathComponent("diagnostics.json")
        var state = AppState(); state.lastFailure = "password=SECRET /Users/private/token"
        state.extraLibraries = ["/Users/private/Games"]
        state.standalone = [Standalone(name: "private", executable: "/Users/private/game.exe", directory: "/Users/private")]
        try Diagnostics.export(state: state, hardware: nil, to: file)
        let report = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(report.contains("SECRET")); XCTAssertFalse(report.contains("/Users/private"))
        XCTAssertTrue(report.contains("unavailable"))
    }
}
