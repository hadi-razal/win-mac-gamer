# Validation record · 22 October 2026

## Confirmed on this Mac

- macOS 27.0, build 26A428, arm64. The native app reports Apple M5, 16 GB memory, Rosetta available, and approximately 286 GiB usable storage during testing. `df` initially reported about 273 GiB; APIs count available/purgeable storage differently.
- Swift 6.4 / Xcode command-line tools are present.
- Native SwiftUI app builds for Apple silicon, launches, renders its setup screen, and detects live hardware. Library and diagnostics UI are implemented; gameplay is not established.
- Local ad-hoc code signature verifies with `codesign --verify --deep --strict`.
- All **14 XCTest tests passed**, with no failures or skips in the final core run. Coverage includes nested Steam VDF parsing, Unicode/escaped paths, Windows drive mapping, real manifest-based installed/incomplete states, corrupt settings, checkpoint retention on simulated bootstrap failure, literal process arguments, verbose output, scoped stop commands, checksums, archive traversal rejection, GTA XML backup/preservation, and allowlisted diagnostics.
- Automatic download of the original upstream Wine Devel 11.18 archive completed through the app, its pinned SHA-256 was verified, and its contents were extracted into a version-specific directory.
- Static inspection of that build's `winemac.so` found no required exported Metal functions. It was rejected as the DXMT candidate. This is not a gameplay result.
- The replacement default is the free upstream `WS12WineCX24.0.7_7` engine, SHA-256 `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c`. It is independent of the commercial CrossOver app. The official engine download was attempted through the native app but timed out before completion. The app displayed the error and preserved recovery state. Download request timeout was subsequently increased to 180 seconds for slow/stalled connections.

## Not yet verified

| Flow | Status |
| --- | --- |
| Selected WineCX archive download, checksum, extraction | Implemented; real download timed out |
| Selected runtime dependency resolution | Unverified |
| GStreamer extraction/relocation if needed | Implemented; initial download interrupted when the candidate changed |
| Windows prefix initialization | Unverified on the selected runtime |
| 64-bit Windows marker program | Implemented; not yet run on real Wine |
| 32-bit Windows marker program | Implemented; not yet run on real Wine |
| Windows Notepad | Launch control implemented; not yet observed |
| DXMT installation and visible Metal rendering | Unverified; layout/export gates may require adjustment after inspecting the downloaded selected engine |
| Windows Steam install, updates and sign-in | Unverified; user completes installer agreements and authentication |
| Rockstar launcher and prerequisites | Unverified |
| GTA V Legacy game download | Not initiated |
| GTA V Story Mode gameplay | Not observed; not marked playable |
| Sustained FPS/frame times/lows | Unavailable |

The simulated setup failure test deliberately uses a tiny test executable that reports a Wine version and fails initialization. It verifies preservation/retry behavior only; it is not evidence of Windows compatibility.

## Next actions

Open `dist/LocalPlay.app`, choose **Continue / verify setup** (or **Set up LocalPlay** when no checkpoint completed), and retry on a working connection. Alternatively download `WS12WineCX24.0.7_7.tar.xz` from the official release and use **Advanced → Import Wine archive**. The selected archive must match the pinned checksum; security checks are not bypassed.

Once this archive is available, inspect the actual engine layout and dependency errors before claiming runtime support. LocalPlay must pass both Windows marker tests and show a Windows program before the Steam step is accepted. Then finish Valve’s Steam installer, sign in with Steam Guard, install GTA V Legacy yourself, authenticate with Rockstar, and observe Story Mode. Follow `BENCHMARK.md` for sustained performance measurement. No large game download is automatic.

## Implementation limits

- The DXMT installer handles the native-DLL release layout and checks required Wine exports. Alternate/builtin release layouts currently stop with an error instead of guessing. The downloaded release may require adapting that path after actual inspection.
- The WineCX engine may bundle media libraries. If `libgstreamer-1.0.0.dylib` is found, the extra GStreamer download is skipped. Otherwise app-managed extraction is attempted; its relocation needs real loader testing.
- An active Windows Steam process inherits its initial environment. Quit it fully before changing HUD environment options. LocalPlay does not promise an existing Steam instance adopts new settings.
- Process creation is logged as a launch request; there is no automatic gameplay/process-name confirmation or automatic FPS sampling.
- Presets apply recognized fields only to an existing GTA XML file. Other games require in-game graphics configuration.
- Logs use safe file redirection and bounded viewing; automatic long-term log rotation is not implemented.
- The app is a local development build, not a notarized public release.

Source, build scripts, test scripts, runtime notices, benchmark instructions and this report are included. These limitations are explicit so a compiled launcher is not mistaken for proven game compatibility.
