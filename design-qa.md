# TradeLab — Arabic Analysis Hub design QA

**Scope:** replace the old "إعدادات الشارت" AlertDialog opened by the chart's More button with the TradingView-style "محور التحليل" sheet. This QA evaluates the native Android sheet, not cTrader authentication or the chart behind it.

## Evidence

- Source truth: `../upload/01-1002877292.jpg` (TradingView Arabic UI; **691 × 1536** pixels).
- First native implementation: `../analysis_hub_capture/tradelab-analysis-hub.png` (**1080 × 2400** pixels).
- Final native implementation: `../analysis_hub_capture_final/tradelab-analysis-hub.png` (**1080 × 2400** pixels).
- Combined full-view comparison: `../analysis_hub_final_comparison.png` (**2160 × 2400** pixels, source at left and native Android output at right).
- Normalization: source image resized to **1080 × 2400** pixels, preserving its essentially identical 0.45 aspect ratio. The Android screen is 1080 × 2400 physical pixels; actual logical dp viewport depends on emulator density. Device status and navigation UI are outside the app-owned scope.
- State: sheet fully open, RTL Arabic, no chart data or authenticated account required, all primary groups visible.
- Tested source commit: `904d6e783c6e9bdf9505dcc299e8cba28360d114`.
- Follow-up implementation: `1c555b63062bfe11dd033730af455f88308126d1`, verified by Android QA run `42070373265` and APK build run `42070373332`.
- Follow-up native capture: `../tradelab_review_20261105/tradelab-analysis-hub.png` (1080 × 2400); new side-by-side comparison: `../tradelab_review_20261105/reference_vs_new_android.png` (2160 × 2400).
- Functionality capture fixtures: `../tradelab_review_20261105/tradelab-object-tree.png` and `../tradelab_review_20261105/tradelab-indicator-templates.png` (both native Android, 1080 × 2400). These fixture screenshots do not depict an authenticated broker account.

## Findings and fixes

### Iteration 1 — P2: vertical offset

- Location: entire AnalysisHubSheet, screenshot `analysis_hub_capture/tradelab-analysis-hub.png`.
- Observation: scaled reference shows handle/title/first row/footer roughly 55–75 physical pixels below the initial emulator capture.
- Fix: lower sheet height fraction from 0.99 to 0.965, adjust title top inset and tools label spacing, add footer separation.
- Verification: final Android capture shows the handle, title, section rules, card rows and footer at approximately the same normalized vertical positions as reference.

### Iteration 2 — P3 icon fidelity and inactive interaction tiles

- Location: indicator, info, replay, layers, publish and Pine Editor icons. The initial Material substitutions were visibly farther from the reference, especially the filled symbol-info and bulb icons.
- Fix: select closer Material Outlined icon variants. Indicator Templates now opens an actual sheet with four presets and a saved personal template. Object Tree now lists the current symbol/timeframe's persisted drawings, with edit and confirm-delete actions. During Replay, only drawings available at the revealed candle time may appear in the list.
- Verification: native `tradelab-analysis-hub.png` capture in Android QA run `42070373265` has the same grid, dividers, RTL text and section rhythm as the normalized source. Real emulator interactions confirmed the new sheets, selection, deletion confirmation and preset callbacks.
- Residual: the replay triangle outline, Pine Editor triangles and indicator-composite icon still use approximate library artwork; exact proprietary TradingView icon paths are unavailable. This is P3, and pixel identity is **not** claimed.

### Final visual pass

- **Fonts/typography:** RTL Arabic wording, title hierarchy, card labels, section labels and footer wording all present; small system-font weight differences are device-dependent P3 polish.
- **Spacing/layout:** the title, dividers, two-column and three-column grids, card heights, gaps and footer match the reference proportions. Content remains visible without clipping.
- **Colors/tokens:** white sheet, pale gray cards, muted gray section headings, black primary text, and pale disabled items follow the reference.
- **Icons/assets:** each tile has a meaningful Material icon or existing native chart glyph. Exact proprietary TradingView icon artwork (especially Pine Editor, publish, indicators, info) is not included; this is P3 visual polish, not a broken control.
- **Copy/content:** the complete Arabic labels, row order and distinct disabled states from the user reference are preserved.
- **Focused regions:** inspected title/handle, 3-item middle row, muted information tiles, and footer in the combined comparison image; each is clearly legible. No further crops necessary.

## Functional checks

- Android UI instrumented tests passed in workflow run `42042980266`. They validate RTL option order, chart-type action dispatch, disabled financial/forecast cards, and a nonblank screenshot.
- Debug APK build and unit tests passed in workflow run `42042980178`.
- Follow-up Android instrumented tests passed in run `42070373265`: AnalysisHubSheet, ChartTypeSheet, DrawingAnchorInteraction, DrawingContextToolbar, ChartObjectTreeSheet, and IndicatorTemplatesSheet. New tests cover empty object-tree, actual drawing edit/delete callbacks, preset application and saved-template action. New native screenshot artifacts were captured for all three relevant sheets.
- Follow-up APK compilation and unit tests passed in run `42070373332`.
- Existing chart settings (appearance, volume, magnet, drawings, reset, history, price alert) remain accessible under **مركز المساعدة → الإعدادات المتقدمة**.
- Compare, Pine Editor, publish and unsupported TradingView-only actions still report unavailable. Forecasts and financial-data tiles stay disabled. No invented feature behavior.
- The screenshot is of the real native Compose component on Android emulator, not a generated mockup or an authenticated live-chart app screenshot.

## Follow-up polish (P3)

- If licensed/exportable source icon assets become available, replace the closest Material icon substitutes for visually exact Pine, indicators and info artwork.
- Typography may vary slightly with actual phone system fonts and font scaling.

**final result: passed** — no remaining P0, P1, or P2 issues in the native Analysis Hub sheet and newly added utility sheets. This result does not verify a broker-authenticated cTrader candle stream or assert literal pixel-by-pixel TradingView ownership assets.

---

# Fibonacci retracement settings — Android design QA, 2026-11-05

**Scope:** native `FibonacciSettingsScreen` opened by editing a FIBONACCI drawing on the existing chart, with three RTL tabs: `نمط` / `إحداثيات` / `الظهور`. This is a separate review from the Analysis Hub above.

## Reference and actual Android evidence

- Source screenshots supplied by the user: `../upload/06-1002878932.jpg` (Style first viewport), `../upload/05-1002878934.jpg` (Style levels scrolled), `../upload/04-1002878937.jpg` (Style appearance controls), `../upload/03-1002878940.jpg` (Coordinates), `../upload/02-1002878947.jpg` (Visibility top), and `../upload/01-1002878948.jpg` (Visibility bottom), each **691 × 1536** physical pixels.
- Android emulator screenshots: `../fibonacci_review_20261105/refined/tradelab-fibonacci-style.png`, `../fibonacci_review_20261105/refined/tradelab-fibonacci-coordinates.png`, and `../fibonacci_review_20261105/refined/tradelab-fibonacci-visibility.png`, each **1080 × 2400** physical pixels.
- Final follow-up captures from actual Android UI test: `../fibonacci_review_20261105/v2_final/v3/drawing-captures/tradelab-fibonacci-style.png`, `tradelab-fibonacci-style-levels.png`, `tradelab-fibonacci-style-appearance.png`, `tradelab-fibonacci-coordinates.png`, `tradelab-fibonacci-visibility.png`, and `tradelab-fibonacci-visibility-bottom.png`, all **1080 × 2400** physical pixels. These cover all six supplied screenshot regions.
- Reference normalization: screenshot resized proportionally from 691 × 1536 to 1080 × 2400 for side-by-side comparison; `../fibonacci_review_20261105/coordinates-side-by-side.png` illustrates the common viewport geometry. Device status/navigation bars differ by Android OS version and are not app-owned.
- The capture mounts the **real Kotlin/Jetpack Compose component on an Android emulator**, not a generated mockup. The test uses known sample XAUUSD candles for coordinate fields; it is **not evidence of authenticated live cTrader candles**.
- Production integration: the editor lives in the existing `ChartScreen` scaffold; chart data providers, Replay logic, and main navigation were not replaced.

## Focused comparison and fixes

1. **Header/tabs:** the white editor, right-aligned Arabic title, close and pencil icons, three RTL tabs, selected dark underline and thin divider match the reference structure. Source and emulator fonts have small system-dependent weight differences (P3).
2. **Style:** line options, extension selector, level-colored swatches, editable numeric inputs, dark checked boxes, and disabled/unchecked levels follow the source ordering. The first iteration used Material text-field outlines; replaced level fields with lighter rounded text input geometry (P2 fixed). A two-color diagonal square replaced an approximate palette icon (P3 fixed). The later native pass split **خط الاتجاه** and **خط المستويات** into independent stroke styles and width controls; a gray dashed trend-line swatch and a separate black solid level-line preview now track the reference. The disabled numeric inputs now use the gray fill/text state from the reference.
3. **Coordinates:** verified two editable price/bar rows with RTL labels, and matched source fixture numbers `4204.64` / `305`, `4169.28` / `302`; controlled field borders and order are visibly close in the side-by-side comparison (P2 fixed).
4. **Visibility:** verifies all referenced groups — ticks, seconds, minutes, hours, days, weeks, months and Ranges — with independent checks and editable minimum/maximum bounds. The scrollable body keeps its own state per tab. The test now asserts that `موافق` and `إلغاء` remain displayed after switching tabs (P2 fixed).
5. **Footer:** fixed action row with `موافق`, `إلغاء`, and ellipsis; verified by screenshots and Compose interaction tests. The test fixture excludes the production application's separate four-destination bottom navigation; this is a fixture difference, not an intentionally removed app navigation bar.
6. **Persistence/behavior:** each level/color/range is saved with the individual drawing. Disabled levels are not drawn, reverse/log levels and fill opacity change rendering, coordinates update actual anchors, visibility is evaluated against the currently viewed timeframe, and cancel does not write. Legacy drawings without a Fibonacci payload are read through a compatibility default. The second pass split independent trend/level line-style and thickness controls. The third pass added the missing bordered dropdowns for level-number format, title horizontal/vertical placement, text horizontal/vertical alignment, and font size; these values affect the rendered labels and are persisted per drawing.

## Remaining differences and acceptance

- Exact proprietary TradingView controls and system glyphs are not copied; native Compose primitives are used. A literal pixel-perfect replica is therefore **not claimed**.
- Line-style options, widths and the trend-line gray swatch are now stored and drawn independently. Existing version-one and version-two drawing payloads remain readable with compatible previous label placement; new payloads use version three.
- This review does not assert that the active broker is authenticated. A real live-feed screenshot requires sign-in separately.
- The reference uses TradingView-specific bottom navigation, status-bar icons and typography; the native emulator uses TradeLab/Android chrome and its platform font. Exact proprietary assets and pixel-for-pixel identity are not claimed, but the reference's editor sections and interactive controls are reproduced.

**Fibonacci result: passed for native UI interaction and persistence**, with remaining P3 platform-specific visual differences explicitly tracked. Third-pass unit tests and debug APK build passed in workflow `42118887634`; Android instrumented interaction tests and six native screenshot captures passed in workflow `42118887346` on commit `b69344a31a853452c8a32044aa9154a0673c2def`. The instrumented test changes line styles, width, label vertical position, text alignment and visibility, checks the saved drawing, and verifies the bottom of each scrollable tab is reachable by touch. Tests use sample XAUUSD candles and do not certify a live cTrader stream.
