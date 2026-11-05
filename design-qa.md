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

## Findings and fixes

### Iteration 1 — P2: vertical offset

- Location: entire AnalysisHubSheet, screenshot `analysis_hub_capture/tradelab-analysis-hub.png`.
- Observation: scaled reference shows handle/title/first row/footer roughly 55–75 physical pixels below the initial emulator capture.
- Fix: lower sheet height fraction from 0.99 to 0.965, adjust title top inset and tools label spacing, add footer separation.
- Verification: final Android capture shows the handle, title, section rules, card rows and footer at approximately the same normalized vertical positions as reference.

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
- Existing chart settings (appearance, volume, magnet, drawings, reset, history, price alert) remain accessible under **مركز المساعدة → الإعدادات المتقدمة**.
- Unimplemented TradingView-only actions are signposted as unavailable; no invented feature behavior.
- The screenshot is of the real native Compose component on Android emulator, not a generated mockup or an authenticated live-chart app screenshot.

## Follow-up polish (P3)

- If licensed/exportable source icon assets become available, replace the closest Material icon substitutes for visually exact Pine, indicators and info artwork.
- Typography may vary slightly with actual phone system fonts and font scaling.

**final result: passed** — no remaining P0, P1, or P2 issues in the native Analysis Hub sheet.
