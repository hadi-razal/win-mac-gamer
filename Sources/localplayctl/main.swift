import Foundation
import LocalPlayCore

@main
struct LocalPlayCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let root = ProcessInfo.processInfo.environment["LOCALPLAY_DATA_ROOT"].map { URL(fileURLWithPath: $0) }
        let paths = Paths(root: root)
        do {
            switch args.first ?? "help" {
            case "inspect":
                try paths.prepare()
                let hardware = await Hardware.detect(at: paths.root)
                print(String(data: try JSONEncoder().encode(hardware), encoding: .utf8)!)
            case "setup":
                let state = try await SetupManager(paths: paths).setup(progress: { print("\($0.step.rawValue): \(Int($0.fraction * 100))% \($0.detail)") })
                print("Setup actions complete: \(state.completed.map(\.rawValue).sorted()). Finish Steam’s interactive installer and login.")
            case "library":
                let state = try StateStore(url: paths.state).load()
                let result = SteamLibrary.discover(paths: paths, extra: state.extraLibraries)
                for game in result.games { print("\(game.id)\t\(game.name)\t\(game.state)\tbuild \(game.buildID)") }
                for warning in result.warnings { print("Notice: \(warning)") }
            case "steam":
                let runtime = try WineRuntime(paths: paths)
                let state = try StateStore(url: paths.state).load()
                guard state.completed.contains(.smoke32), state.completed.contains(.graphics) else { throw LocalPlayError.message("Complete setup before launching Steam.") }
                let result = try await ProcessRunner.run(try runtime.steamCommand(), log: paths.logs.appendingPathComponent("cli-steam.log"), timeout: 86_400)
                print("Steam launcher exited \(result.status); this does not establish gameplay.")
            case "stop":
                let result = try await ProcessRunner.run(try WineRuntime(paths: paths).stopCommand())
                print("LocalPlay environment stop status: \(result.status)")
            default:
                print("localplayctl inspect | setup | library | steam | stop\nSet LOCALPLAY_DATA_ROOT to isolate development data.")
            }
        } catch { fputs("LocalPlay: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
