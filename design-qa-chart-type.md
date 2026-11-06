# TradeLab — chart-type picker reference QA

## Scope and evidence

- Reference: `../upload/01-1002875321.jpg` (TradingView Arabic Android UI, 691 × 1536).
- Native rendering: `../chart_type_capture_good/tradelab-chart-type-sheet.png` (Android emulator, 1080 × 2400), from Drawing Interaction QA run `42036426591`.
- Source: `app/src/main/java/com/example/feature/chart/ChartTypeSheet.kt`, `ChartTypeGlyph.kt`.
- Verified commit: `d1477a63e22ef7a805a45c5944b83073b1497a53`.

## Visual comparison

| Element | Result |
| --- | --- |
| White bottom sheet, rounded top corners, centered gray handle | Matches reference layout. |
| Arabic title on the right | Matches wording, alignment, contrast, and approximate size. |
| Three-column RTL grid of 21 labels | Correct, all seven rows visible in Android screenshot. |
| Tile background, spacing, and rounded corners | Close visual match. Grid starts at equivalent vertical position and final row ends near reference position. |
| Financial chart glyphs | Thin outlined, chart-specific icons approximate reference; not proprietary pixel-identical artwork. |
| Current type highlight | Dark selected tile works. Test selects actual `شموع`, while reference depicts `مدى`; this is intentional live-state behavior. |

## Functional verification

- Android screenshot/interaction tests: success, workflow run `42036426591`.
- Debug APK compilation and unit tests: success, workflow run `42036426682`.
- Supported choices: 13 real-OHLC-derived display modes with native canvas rendering.
- Unavailable choices: 8 data-dependent modes display an honest unavailable message instead of synthetic data.
- UI capture includes an explicit nonblank screenshot assertion to prevent false visual verification.

## Constraints

- The screenshot is a native component rendered on an emulator, not a live authenticated cTrader chart screen.
- Android status/navigation bars and current selection differ from the original TradingView device; only the chart-type sheet is evaluated.
- Pixel-identical proprietary fonts and icons are not asserted.

**final result: passed** — reference-equivalent layout and functioning type-selection UI; no open critical/major issues in the picker surface. Broker-authenticated chart rendering is out of scope of this visual QA.
