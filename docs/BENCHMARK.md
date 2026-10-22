# Sustained gameplay benchmark

No gameplay measurements have been collected. Average FPS, frame-time behavior, and lows remain **unavailable**.

1. Record Mac/GPU, memory, macOS build, Wine release and SHA, DXMT release and SHA, Steam app ID and build ID, Rockstar version, graphics settings, screen mode and resolution. Save LocalPlay diagnostics and a copy of GTA settings.xml. Updates invalidate prior results until retested.
2. Plug into power, note room conditions, keep ventilation clear and use the same display. Do not modify global power or security settings. The MacBook Air is fanless; short runs cannot establish sustained performance.
3. Use GTA Legacy’s built-in benchmark or the same 15–20-minute Story Mode driving route. Keep time/weather and route consistent when possible. Never test GTA Online in LocalPlay.
4. Warm shader caches with an initial pass. Label that cold pass separately. Keep the cache when comparing settings under the same runtime/backend.
5. Try Balanced at 1440×900, moderate textures, reduced shadows/reflections, MSAA off, Advanced Graphics off. Try Performance at 1280×800. Seek a stable 30 FPS target using supported game controls if needed; neither target nor performance is guaranteed.
6. Repeat the same scene after 15–20 minutes to detect thermal decline. Change one setting at a time. Save the prior configuration and restore it for comparisons.
7. Record only actual readings from the game’s benchmark output or a supported Metal HUD / capture tool. Do not derive 1% lows from average FPS. If frame-time samples or reliable low statistics are unavailable, mark them unavailable.
8. Confirm visually that DXMT rendered the scene and inspect its initialization log for backend evidence. A DLL being installed, a Steam process existing, or a launcher exiting successfully is not enough.

| Run | Game/build | Runtime/backend | Resolution/preset | Warm cache | Duration | Average FPS | Lows | Frame-time notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Not run | GTA Legacy / unavailable | WineCX 24.0.7 + DXMT 0.80 candidate | Unapplied | Unavailable | Unavailable | Unavailable | Unavailable | Gameplay unverified |
