# TradeLab — Stage 3a closed-bar Pine language runtime handoff (2026-11-24)

**Working branch:** `feat/pine-stage3a-language-runtime-20261124`  
**Draft PR:** [#645](https://github.com/775878805Osamaha/TradeLab/pull/645) → `feat/pine-stage2-v6-frontend-20261123` (**#643**, still stacked on unmerged **#642**). **Owner chooses / merges only.** PR #644 will NOT merge, and it is NOT a dependency. No main/Kotlin/APK/Release/other repositories touched.

## Selective transplant before Runtime

- **Taken from #644 by hand:** `x == na` / `x != na` rejection with use-`na(x)` error, `ta.ema/ta.rsi` length integer/type/qualifier and positive literal enforcement, with **2 new tests** adapted to `pine_v6_frontend_test.dart` on #643 architecture.
- **Not taken:** alternative `pine_frontend_*.dart` Lexer/Parser/AST/Semantic stack, `chart_indicator_library.dart` overwrite, `verify-flutter-range.yml` overwrite, alternate docs or duplicate workflow. The **existing #643** Lexer, Parser, AST and semantic stack remain authoritative. Chart/library changes after the transplant are specific to Stage 3a, not copied from #644.
- Shared paths were inspected and old semantics preserved. The main existing Flutter test gate remains unchanged; the new branch has a **separate** `pine-v6-stage3a-no-apk.yml` to avoid touching the five shared paths.

## Source implementation completed so far

1. `flutter_app/lib/chart/pine_v6_semantic.dart`: ported direct-`na` and simple-int length checks; existing scope, type, qualifier, named-UDF and loop-control checks retained.
2. `flutter_app/lib/chart/pine_v6_language_runtime.dart` **new**: bounded, per-closed-bar executor for the #643 AST, reusing Stage 1 `PineRuntimeBudget`; `var` and closed-bar `varip`, reassignment, `if/else`, ternary, switch-arm blocks, `for`/`while` with break/continue, finite loop cap, numeric scalar UDF with independent written-call-site SMA accumulators, input.int/float, math.abs/min/max, na/nz. Rejects unknown requests/plots/TA functions instead of faking outputs. Old `PineSubsetProgram` remains the execution path for all already-supported numeric scripts; do not bypass invalid legacy script periods via new fallback.
3. `flutter_app/lib/chart/chart_indicator_library.dart` and `chart_indicator_engine.dart`: **manual additive integration**, gate saved Stage 3a source through new compiler, retain existing saved scripts and all old numeric indicator paths. New scripts use verified current Replay prefix in chart; old scripts use old evaluator. No extra `pine_frontend_*.dart` files imported.
4. `flutter_app/test/pine_v6_language_runtime_test.dart` **new**: manual var counter/first-close var, closed-bar varip, if/else, historical loop/nz/na, break/continue, for/while limit error, conditional UDF SMA history, two instances, two Replay sessions, 50→20→30 no-future/identical direct output, safe unsupported call, legacy numerical differential, switch return, saved-library-and-chart integration, and rejection of legacy invalid period.
5. `flutter_app/test/pine_v6_frontend_test.dart` +2 portable #644 rules.
6. `.github/workflows/pine-v6-stage3a-no-apk.yml`: runs full Flutter analysis + Pine, Replay, Range, chart and paper-regression tests, no APK. `docs/PINE_STAGE3A_SUPPORT_MATRIX_2026-11-24.md` is the explicit parsed/executed/not-yet-supported matrix.

## Verified test evidence and status

**First completed CI before chart wiring:** [#45281977095](https://github.com/775878805Osamaha/TradeLab/actions/runs/45281977095) **completed/success** on `2be26b5577f071396e9b1f64ecc70b91a3ddf3c1`, actual GitHub log **976 main + 4 separately verified drawing + 11 timezone = 991 PASS / 0 FAIL**, Flutter analyze success; all first **11** runtime tests passed. This is NOT a green claim for subsequent chart integration changes.

**Final exact-source production CI:** [#45283899469](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283899469), source commit `42d10fbd7a790e7495364e197f9422855d59e2ba`, **completed/success**. Actual GitHub Actions job log: **982 Flutter regression tests + 4 independent drawing selection tests + 11 Yemen chart scale tests = 997 PASS / 0 FAIL**, Flutter Analyze success. All **17** new Stage 3a runtime tests and **2** ported #644 frontend cases explicitly passed. Existing Pine, Replay, Range, chart and paper-regression tests remain green in the same CI. No local Flutter installed, no Android device or APK tests.

**Script-level var mutation test:** temporary branch `test/pine-stage3a-var-mutant-no-pr-20261124` at mutant commit `552fabab93ade1768a1cf346e8e6dd5a2aae2013` deliberately uses static shared var state; [run #45283233812](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283233812) **PENDING**, no PR. A green run would indicate the tests are too weak and need strengthening; do not count intentional failures as production failures.

Local Flutter/Dart executables **not installed**. No local Flutter Analyze, emulator, physical device or APK executed.

## Official semantics and known limits

- [TradingView v6 execution model](https://www.tradingview.com/pine-script-docs/language/execution-model/): confirmed historical bar execution; `var` commits across bars, while `varip` escapes intrabar rollback on realtime bars. **This implementation handles confirmed historical candles only.** Replay treats each prefix candle as closed. No realtime tick/recalculation/rollback tests, no claim of full live `varip`.
- [TradingView v6 user functions](https://www.tradingview.com/pine-script-docs/language/user-defined-functions/): each *written* call-site has an independent variable and historical series scope, and conditional calls can skip some bar executions. New SMA state keys by AST call expression + enclosing written UDF call site; conditionally skipped UDF sites add no SMA samples.
- [TradingView loops](https://www.tradingview.com/pine-script-docs/language/loops/): `for...in` exists for arrays/maps/matrices, but collection iteration is NOT implemented (Stage 3b or after).
- **Incomplete v6 coverage**: `if` and `switch` statement blocks/last-expression UDF return supported; the Stage 2 grammar does not yet parse `x = if ...` or `x = switch ...` expression forms, and those are not claimed. Full UDF type/overload/UDT/tuples, other builtins, advanced drawing and cross-timeframe request.* remain unsupported. No broker order logic changed.
- Full-prefix Replay rebuild is deterministic **O(bars × supported AST work)**; not incremental checkpoints. Budget and time checks are cooperative (not preemptive isolates), so live Android UI frame performance is unverified.

## Merge instructions and next task

Review owner #642 → after owner merge carefully rebase/retarget #643 onto `test/flutter-all-fixes-20261116` and rerun CI → owner merges #643 → rebase/retarget draft #645 to the integration branch and rerun entire CI → **owner alone** merges #645. Never merge #644; owner will close it. Nothing is merged now.

Next technical work after green CI and owner review: Stage 3b built-in function registry and v6-compatible TA/math/array library, tick-level rollback/realtime `varip` design, full if/switch expression grammar, cancellable isolate, and performance tests. No V10, no OMEX, no OMX ERP.

## Subsequent integration and mutation QA — current checkpoint

- Integrated saved-source/chart engine via existing `chart_indicator_library.dart` and `chart_indicator_engine.dart` (manual edits only); no PR #644 file copied. The original legacy numeric evaluator remains first for supported scripts, advanced AST is admitted only after whitelist check and Stage 3a construct presence; invalid legacy periods never fall through as acceptable Stage 3a.
- [CI #45282914169](https://github.com/775878805Osamaha/TradeLab/actions/runs/45282914169) **failed 978 PASS / 2 FAIL** on source commit `ed46b560fbcb907f8f23ac983533ed992cc1fe1e`: both failures were old editor regression checks expecting Arabic `السطر` in unsupported-script error messages. The numeric calculations and Stage 3a tests passed; fixed the diagnostic contract in `chart_indicator_library.dart` at `731dfcbf3916744cbd403d650a5a23613914e079`. Later CI reruns required.
- Runtime tests expanded to **17** cases at `42d10fbd7a790e7495364e197f9422855d59e2ba`, adding written-call-site isolation both for `var` inside a UDF and for `ta.sma` histories inside two distinct written calls. [Run #45283899469](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283899469) is **awaiting completed CI verification**; do not claim 17 PASS yet.
- **Actual intentional var-mutation proof (final):** temporary branch `test/pine-stage3a-var-mutant-no-pr-20261124` replaced per-instance persistent `var` values with one shared static map; first run #45283233812 also caught 2 old editor-message failures. After applying the unrelated editor-message fix to that throwaway branch, [GitHub Actions #45283643004](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283643004) **completed/failure by design: 978 PASS / exactly 2 FAIL**. The **only** failed cases are the real-source Pine `var` two-instance test (expected 4, actual 6.0) and independent Replay sessions (expected 1, actual null). GitHub job log supports both assertions. Then the temporary branch was force-with-lease **restored to clean Stage 3a HEAD `fc5b8d7b1c856ec0c93df809437308cd82f151e4`**, no mutation PR and no mutant in #645. This is controlled test sensitivity, not a production regression.

## Final verification / correction log

- [CI #45282914169](https://github.com/775878805Osamaha/TradeLab/actions/runs/45282914169): **978 PASS / 2 FAIL** on the first chart-integration commit. Existing Arabic saved-script editor tests required the message to contain `السطر`; the new compiler's error omitted it. Corrected by preserving `السطر 1، العمود 1` and error code in `chart_indicator_library.dart`, code commit `731dfcbf3916744cbd403d650a5a23613914e079`. This was a **real failure, fixed**, not silently counted as a pass.
- Added 2 additional callsite tests to the runtime suite: `var` inside the same function at 2 written callsites has independent persistent history, and two independent `ta.sma` written callsites retain disjoint SMA histories. Commit `42d10fbd7a790e7495364e197f9422855d59e2ba`.
- [Final exact-source CI #45283899469](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283899469) **997 PASS / 0 FAIL**, all **17** Stage3a runtime and **2** ported #644 frontend tests passing, analyzer success. `docs/` changes after source commit do not change Dart behavior; new workflow ignores docs-only push updates.
- [Intentional mutation #45283643004](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283643004) **978 PASS / exactly 2 expected FAIL**; no PR, mutant branch restored to clean commit and excluded from PR #645.

**Actual limitations:** `varip` historically closed-bar execution only; **no realtime open-bar rollback**. Per-call-site SMA state exists and is checked by two distinct written callsites, but **general v6 history for arbitrary conditional expressions and collection UDFs is incomplete**. Parser does **not** support full `x = if` / `x = switch` expression grammar. `for...in` collection iteration is deferred. Analysis/execution currently synchronous with cooperative budgets; no proof of non-blocking Android chart interaction or tick-feed equivalence. Full Replay rebuilding is correct in tests but O(prefix × AST cost), no checkpoint optimization.
