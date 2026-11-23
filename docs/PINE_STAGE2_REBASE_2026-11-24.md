# PR #643 — exact rebase / conflict reconciliation (2026-11-24)

## Verified
- Stage 1 PR #642 merged to `test/flutter-all-fixes-20261116` at `a8ee02924701afdb62f333172381360ca1ca8148` (2026-11-23T23:08:44Z).
- Original Stage 2 PR #643 head: `a8f7db3e99123489771d260727a839c1e4e7e2a9`, based on Stage 1 `ef917ad2c3dd3dc3e036e17b9dc1ead2d59631ee`.
- Original #643 head preserved at `backup/pine-stage2-before-rebase-20261124`; no history is lost. Rebased source was combined as a single reviewed consolidated commit on top of the merged integration branch (not a per-commit 39-commit replay).
- New source is not merged; owner merges only. No APK, no main/Kotlin/V10/OMEX/OMX ERP.

## Important provenance
The Stage 1 merged tree unexpectedly contains files from the competing #644 `pine_frontend_*.dart` and test `pine_frontend_v6_test.dart`. The code was inherited via #642, **not via merging PR #644**. Removing it while rebasing #643 would lose previously merged files and break older tests. We therefore retain it for backwards compatibility while keeping `pine_v6_*` as the supported primary saved-script frontend. Both test suites run; removal is a separate future owner decision.

## Five overlapping paths — manually resolved
1. `flutter_app/lib/chart/chart_indicator_library.dart`: start with canonical #643 source, retain its `PineV6Frontend().prepare` in `_compileSeries`/user-facing `compileError`; preserve merged #642 compatibility import `pine_frontend.dart` and the public `PineFrontendAnalysis get frontendAnalysis` accessor used by original alternate tests. Neither parser is dynamically selected for the main saved-script executor; canonical #643 is selected.
2. `.github/workflows/verify-flutter-range.yml`: preserve merged #642 workflow trigger branches `main`, `test/flutter-all-fixes-20261116`, `feat/pine-stage1-instance-safe-runtime-20261123`, `workflow_dispatch`, full prior test list, `pine_frontend_v6_test.dart`; insert `pine_v6_frontend_test.dart`. Both old and canonical Stage 2 frontend suites are checked; no APK.
3. `docs/PINE_STAGE2_HANDOFF_2026-11-23.md`: two independent reports collided. The target alternate report was archived intact at [PINE_STAGE2_ALTERNATIVE_644_IMPORTED_VIA_642_2026-11-23.md](PINE_STAGE2_ALTERNATIVE_644_IMPORTED_VIA_642_2026-11-23.md); canonical #643 report was restored intact under the original name, with this cross-reference.
4. `docs/HANDOFF.md`: preserve complete merged #642 handoff and prepend all **3 distinct original #643 report lines** in their original wording, plus new reconciliation pointer. Existing historical lines not dropped.
5. `docs/CHANGE_REPORTS.md`: preserve complete merged #642 log and prepend all **15 distinct original #643 report lines**, plus this reconciliation record. Existing historical lines not dropped.

## Added Stage 2 source files (verbatim from #643)
`.github/workflows/pine-v6-stage2-no-apk.yml`, `docs/PINE_V6_LANGUAGE_SUPPORT_STAGE2_2026-11-23.md`, `flutter_app/lib/chart/pine_v6_ast.dart`, `pine_v6_frontend.dart`, `pine_v6_lexer.dart`, `pine_v6_parser.dart`, `pine_v6_semantic.dart`, and `flutter_app/test/pine_v6_frontend_test.dart`.

## Verification and Vercel
- Flutter CI on the rebase commit: **PENDING**. The old #643 978/0 run predates the rebase and is not substitute proof.
- Before rebase, the PR's Vercel commit status reported **failure: Deployment rate limited — retry in 24 hours**. This is a hosting quota/availability issue, not a Flutter compilation error. Investigate whether branch protection requires it separately.
- No #645 rebase now; wait for owner to merge #643 into the integration target, then rebase #645 with fresh Flutter CI.
