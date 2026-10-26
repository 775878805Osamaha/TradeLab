# Chart reference verification

Reference: supplied 864×1536 screenshot (`reference.png`).
Base: c68347b99edb005b12e79f79bbe2fa6f216d2fe8 (main).
Work is isolated in PR #384. No engine or execution changes.

## Measured target geometry

| Region | Reference pixels | At 400dp viewport width |
|---|---|---|
| Price axis | x=745–864 | 55dp |
| Drawing rail | x=14–110, y=164–1190 | width 44dp |
| Time axis | y=1214–1264 | 23dp |
| Chart control strip | y=1264–1361 | 45dp |
| Navigation container | x=14–849, y=1374–1500 | height 58dp |

The reference does not expose the source device density. CI uses 864×1536 at
346dpi (about 400dp width); these dp values are an explicit inference.

## Actual evidence and repairs

- Initial local Gradle bootstrap failed: `java.net.SocketException: Network is unreachable`.
- CI #885 compiled Kotlin; 467 tests ran, 1 failed in
  `AdvancedChartTests.test ChartDrawing Room entity serialization and deserialization`
  (`java.lang.RuntimeException at AdvancedChartTests.kt:222`).
- Removed the new Android JSONObject dependency from drawing persistence and added
  Arabic annotation and OHLC magnet regression tests.
- CI #886 on 48a80e1 passed unit tests and assembled the APK.
- Actual emulator capture #75 on f9e8175 reviewed, not presented as final evidence.
  It exposed: duplicate large Replay control, history paging overlay over the axis,
  double system inset spacing, light system bars, and generic drawing icons.
- Follow-up repairs remove these overlays in immersive layout, consume system insets
  once, use dark system bars, add native reference vectors, and align price-axis
  gestures physically right in RTL. Advanced controls remain in the detail layout.
- Reference and real capture are compared by `scripts/compare_chart_reference.py`.
  Workflow publishes an overlay, difference image, accessibility coordinates and
  raw screenshots. Native Activity tests exercise navigation, menus and Replay.

## Acceptance status

**Pending final emulator comparison and native interaction results.**
No pixel-perfect or 60FPS claim. Market-dependent candles, quotes, timestamps and
system status values must vary. No reference prices are hardcoded.
