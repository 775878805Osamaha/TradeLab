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


## Final post-rebase verification (exact source code)
- Conflict resolution commit: `a110fe8ca6a03d63ad1d8a96b891c3b05e6e8d5d`, parent `a8ee02924701afdb62f333172381360ca1ca8148`. GitHub PR mergeable = true (not conflicted).
- [PR full Flutter CI #45287365632](https://github.com/775878805Osamaha/TradeLab/actions/runs/45287365632) **FAILED: 978 main tests passed / 1 failed**. The sole regression was inherited #642 test `pine_frontend_v6_test.dart: unsupported v6 scripts save cleanly without evaluating fake data`. Legacy UI expected Arabic `غير مدعوم`; canonical #643 error contained source line and code `not_yet_supported` but omitted that wording. This error was **real and fixed**, not a Vercel failure.
- Repair code commit `9371a44df92b758669117faa3c5c7b62a154586e`: retain canonical error code, line and column; append ` — غير مدعوم بعد` only for `not_yet_supported`. No numeric/parsing/runtime behavior changed.
- [Final exact-source PR full Flutter CI #45288069347](https://github.com/775878805Osamaha/TradeLab/actions/runs/45288069347): **completed/success**. Actual CI logs: **979 primary Flutter tests + 4 independent drawing checks + 11 Yemen timezone/scale tests = 994 PASS / 0 FAIL**. Flutter Analyze success. **25 / 25 `pine_v6_frontend_test.dart` canonical tests** and **16 / 16 `pine_frontend_v6_test.dart` inherited compatibility tests** passed. Full existing Replay/Range/chart/paper tests also included.
- [Dedicated Stage 2 full regression #45288058896](https://github.com/775878805Osamaha/TradeLab/actions/runs/45288058896): **completed/success**, **963 main + 4 drawing + 11 timezone = 978 PASS / 0 FAIL**; Flutter Analyze success. This workflow checks the canonical 25 frontend cases; the PR workflow above also checks 16 inherited alternative tests and is the more inclusive acceptance gate.
- Subsequent documentation-only report commits do not change the tested Dart source; the CI results above refer to exact code commit `9371a44df92b758669117faa3c5c7b62a154586e`.
- GitHub's [branch metadata](https://github.com/775878805Osamaha/TradeLab/tree/test/flutter-all-fixes-20261116) reports `protected:false`, `required_status_checks.checks:[]`; the repository ruleset list was empty. Direct branch-protection endpoint denied by the connected GitHub App (403), so deeper administrator policy cannot be read. This indicates Vercel is **not configured as a required GitHub branch-protection check in the visible rules**; the [Vercel commit status](https://github.com/775878805Osamaha/TradeLab/pull/643) nonetheless reports `failure: Deployment rate limited — retry in 24 hours` and may leave the PR visually `unstable`. This is a separate hosting rate limit, not a Flutter failure, and must not be silently called green.
- **Owner decision:** PR #643's code is ready for owner merge based on no conflicts and full Flutter CI green. Assistant did **not merge**. PR #645 remains stacked and unmodified; rebase it only **after** owner merges #643, with new full CI.
