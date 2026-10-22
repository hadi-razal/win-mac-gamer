# Win Mac Gamer (LocalPlay)

A native SwiftUI macOS application for running owned Windows software locally through Wine, with Windows Steam integration and a DirectX 10/11-to-Metal backend.

LocalPlay is the application name; Win Mac Gamer is the project repository. Built by Hadi Razal.

**Development build, not yet a validated game runner.** The app compiles and its core logic is tested. Actual Wine execution, Windows Steam login, DXMT rendering, and GTA V gameplay have not been established on this Mac. See [validation](docs/VALIDATION.md) for the exact boundary. This is not a cloud or streaming application.

## Build and open

Requires macOS 14+, Apple silicon with Rosetta, and Xcode / Swift tools. The development machine reports macOS 27.0 (26A428), arm64, 16 GB memory; `df` reports about 273 GiB available. Metal and some hardware queries are restricted inside the development sandbox; the native app detects them on launch.

```sh
./scripts/test.sh
./scripts/build.sh
open dist/LocalPlay.app
```

The build is ad-hoc signed for local use. It is not notarized for public distribution. No third-party Swift packages are required. Swift language mode 5 is selected for compatibility with the host's Swift 6.4 preview toolchain; the native SwiftPM build system is used because its Xcode build-system mode currently behaves differently on this preview installation.

## Architecture

| Module | Responsibility |
| --- | --- |
| `Sources/LocalPlay` | Native SwiftUI interface, setup, library, game details and diagnostics |
| `Sources/LocalPlayCore/SetupManager.swift` | Pinned runtime installation, environment creation, execution checks and retry checkpoints |
| `Sources/LocalPlayCore/ProcessRunner.swift` | Structured process arguments, output redirection, Wine environment and prefix-scoped stopping |
| `Sources/LocalPlayCore/SteamLibrary.swift` | Valve VDF/ACF parsing, Windows drive mapping and actual installed-game discovery |
| `Sources/LocalPlayCore/Downloads.swift` | Asynchronous downloads, progress, SHA-256 validation and archive checks |
| `Sources/LocalPlayCore/GameConfiguration.swift` | GTA XML backups and edits; allowlisted diagnostics export |
| `Sources/LocalPlayCore/Models.swift` | Hardware detection, persistent settings and setup state |
| `Sources/localplayctl` | Command-line diagnostics and setup using the same core |
| `Tests/LocalPlayCoreTests` | Fourteen automated tests for parsing, paths, persistence, process safety and recovery |

The interface starts no game downloads automatically. Wine provides Windows compatibility, Rosetta handles x86 CPU translation where needed, and DXMT is the selected DirectX 10/11-to-Metal rendering path. Steam and Rockstar retain responsibility for authentication, ownership, DRM, updates and prerequisite installation.

## Use

1. Open `dist/LocalPlay.app` and choose **Set up LocalPlay**. Setup checks available storage and Rosetta, downloads the pinned Wine release, verifies its SHA-256, and prepares GStreamer media support. It does not install games.
2. Setup creates its own Wine prefix, checks both `system32/cmd.exe` and `syswow64/cmd.exe` with fixed test markers, then installs DXMT. It refuses to claim a working graphics backend when required components or Wine exports are absent.
3. Valve's real Windows Steam installer opens. Complete its installer and any agreements yourself, then use **Open Steam** to sign in, including Steam Guard. LocalPlay has no Steam login form and collects no passwords.
4. Find **Grand Theft Auto V Legacy**, app **271590**, in your owned Steam library. The Library page can open Steam's installation page. Review storage requirements and start the large download yourself.
5. Install Rockstar's launcher and prerequisites through the normal game / Steam flow. Rockstar authentication is required. Run **Story Mode only**. Rockstar documents disabling BattlEye for Story Mode using its launcher setting; GTA Online is unsupported. No DRM or anti-cheat bypass is implemented.
6. Refresh the library after installing or updating. Games come from `libraryfolders.vdf` and `appmanifest_*.acf`, not a saved marketing list. Use **Launch through Steam** for authentication. Launch requested does not establish that a game is running.

Legacy and Enhanced (**3240220**) are separate. Enhanced is experimental and its launch is disabled here because this DXMT stack does not supply DirectX 12. Unknown games are labelled unknown; there are no promises about compatibility or FPS.

## Runtime lock

| Component | Pinned selection | Verification |
| --- | --- | --- |
| Wine | Sikarugir free WineCX 24.0.7 engine revision 7, `WS12WineCX24.0.7_7.tar.xz` | Published SHA-256 `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c` |
| Graphics | 3Shain DXMT v0.80, native DLL release archive | Resolve only official v0.80 release asset; verify GitHub asset digest if published, record local SHA-256 |
| Media | GStreamer 1.28.5 universal runtime package | Validate package signature using `pkgutil --check-signature`, record SHA-256 |
| CPU translation | Apple Rosetta | Execute fixed x86_64 `/usr/bin/true` preflight |
| Steam | Valve Windows installer, mutable upstream endpoint | HTTPS official download and PE header validation; no published fixed digest asserted |

The selected engine is a free Wine build from Sikarugir's official Engines releases, based on the open-source CrossOver Wine 24.0.7 code (Wine 9). It does not depend on the commercial CrossOver application or a paid license, and no installed commercial application is copied. The same upstream currently lists this engine alongside its newer Wine 11 engine. DXMT supports macOS 14+ and Wine 8+ but requires specific visible `winemac` APIs. LocalPlay checks key exports before installing it. **The exact engine/DXMT combination remains a candidate until real rendering is tested.**

The first downloaded candidate, Gcenx Wine Devel 11.18, failed static DXMT export inspection: the required exported Metal APIs were absent. LocalPlay changed to the free WineCX engine rather than hiding that problem. The original download is retained separately; it is not reused as the active game runtime.

GStreamer upstream documents installation into `/Library/Frameworks` for all users. LocalPlay instead extracts the signed package into its own `Frameworks` directory and supplies framework/plugin paths per process. **This relocation is not runtime-validated** and may need packaging adjustments if the framework uses absolute dependencies. LocalPlay never runs the package installer or changes system frameworks.

No Linux Proton binaries, CrossOver installation, D3DMetal, or commercial wrapper payloads are used. See [notices and upstream source links](docs/THIRD_PARTY_NOTICES.md).

## Files and recovery

Data lives in `~/Library/Application Support/LocalPlay/`:

- `Runtime/winecx-24.0.7_7-dxmt-0.80/`: version-specific runtime.
- `Environments/Steam-winecx-24.0.7_7-dxmt-0.80/`: isolated Windows Steam prefix and games.
- `Frameworks/`, `Downloads/`, `ShaderCaches/winecx-24.0.7_7-dxmt-0.80/`, `Logs/`, `Backups/`.
- `settings.json`: atomic saved checkpoints, preferences, library shortcuts, runtime metadata and archive digests. Corrupt JSON is reported rather than silently overwritten.

Retry setup after fixing an error; completed stages and games are kept. If the network download is interrupted, that file restarts from the beginning while completed setup stages remain. Downloads become cache files only on completion. Remove only a bad cached download after a checksum error. Failed extraction uses disposable staging directories. An incomplete runtime folder is never overwritten: rename it as a backup when prompted. DLL replacement backs up originals and rolls back a partial copy failure.

**Advanced** supports importing the exact Wine archive, the official DXMT v0.80 archive, or the signed GStreamer package. Wine imports use the pinned checksum; DXMT local imports record a digest and rely on the user to obtain the correct official version. macOS prompts must be approved through its normal security flows. No quarantine removal, Gatekeeper bypass, SIP changes, or Rosetta auto-install occurs.

LocalPlay replaces Wine-created symlinks to native user Documents/Desktop/media directories with prefix-local directories during initialization. It never changes the linked native directories. Existing macOS Steam and other prefixes are untouched. Wine still runs under your account's normal file access; this prefix is an environment separation mechanism, not a security sandbox for untrusted executables.

Stop commands are `wineserver -k` with only LocalPlay's `WINEPREFIX`; the GUI requires confirmation because all programs in that environment close. There is no global Wine kill. Removing a standalone shortcut or extra library reference keeps the game files. LocalPlay has no automatic uninstaller.

## External libraries and standalone programs

Configure external Windows Steam libraries in Windows Steam first. Wine's normal `Z:` mapping exposes macOS paths (for example `Z:\Volumes\Game SSD\SteamLibrary`). LocalPlay resolves `C:` into its prefix and other mapped drives through that prefix's `dosdevices`. Additional folders can be added under Library → Add. Filesystem access and an external drive must be available when launching.

Standalone `.exe` files require an explicit working directory. Advanced arguments use one literal argument per line. No user-provided shell command is evaluated.

## Performance and presets

Balanced suggests 1440×900; Performance suggests 1280×800. For GTA Legacy, the app can edit an existing prefix-local `settings.xml`, backing it up first. It changes recognized resolution, texture, shadow, reflection and MSAA fields only; it keeps unrelated settings. Quit the game before applying. Disable Advanced Graphics in GTA manually. For other games, presets remain saved references: set graphics inside each game's supported UI.

Start with moderate textures, lower expensive shadows/reflections, MSAA off, Advanced Graphics off. A stable 30 FPS target is a candidate for the fanless Air, not a measured result. [Benchmark procedure](docs/BENCHMARK.md).

The optional Apple Metal HUD is requested through `MTL_HUD_ENABLED=1`. Support and readings need actual testing. Fully quit Windows Steam (including its tray process) before launching to change inherited HUD settings; an existing Steam process does not adopt a new launcher's environment. Shader caches persist per runtime/backend combination; DXMT further manages executable caches. No synchronization, CPU priority, RAM cleaner, or global GPU tweaks are enabled.

Library refresh and log refresh are user-triggered. There is no continuous game polling, animated FPS counter, or background account service. LocalPlay does not automatically establish game-running state and does not invent metrics.

## Diagnostics and testing

Timestamped runtime output is redirected to files so verbose processes cannot deadlock on full pipes. The viewer reads a bounded 64 KiB tail when requested. Logs can contain personal information; do not share them without checking. Export Diagnostics writes only an allowlist of hardware/runtime/checkpoint fields and unavailable performance fields; it excludes account files, raw logs, arguments, and personal paths.

`localplayctl inspect`, `setup`, `library`, `steam`, and `stop` expose the same core for diagnosis. Use `LOCALPLAY_DATA_ROOT=/absolute/development/folder` to isolate development data. The GUI also honors that environment variable when launched directly.

If Steam fails to sign in or Rockstar fails to initialize, inspect the local logs and finish the prerequisite installer in the normal client. DXMT initialization failure, missing exports, macOS security denials, and network failures are blockers to investigate, not proof that the game works.
