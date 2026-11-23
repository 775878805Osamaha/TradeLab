# TradeLab — Pine Stage 1 handoff (2026-11-23)

> Branch: feat/pine-stage1-instance-safe-runtime-20261123  
> PR: https://github.com/775878805Osamaha/TradeLab/pull/642 (DRAFT — NOT MERGED)  
> Base: test/flutter-all-fixes-20261116 at 6f7cd68fe4322ec0161e7b690d08a00814be57e1  
> Prior audit: docs/PINE_V6_STEP0_AUDIT_2026-11-23.md in PR #641  
> Scope: general Pine subset, isolated runtime instances, Replay; exclude personal V10 completely. No APK, no main, no other repositories.

## A. Source changes actually made

1. **flutter_app/lib/chart/pine_runtime_core.dart** (new): PineValue typed numeric NA vs strict v6 boolean; numeric NA propagates through arithmetic, all comparisons involving missing numeric values produce false as TradingView v6 specifies; PineSeries retains bounded historical values and returns numeric NA or boolean false on unavailable prior bars. PineRuntimeLimits/PineRuntimeBudget enforce per-run step, allocated-value, history and cooperative monotonic deadline ceilings. Exceeding the limit throws a typed PineRuntimeException, not a synthetic value.
2. **flutter_app/lib/chart/pine_subset_program.dart** (extended): PineBarExecutor reuses existing private AST and runs one real source candle per advance. Separate AST memo, series history, TA accumulators and outputs; supports existing bounded math/ta/input subset. Original bulk evaluate() is retained and compared against streaming output. withInputs and evaluateIncrementally are additive. Not a general Pine v6 compiler.
3. **flutter_app/lib/chart/pine_indicator_instance.dart** (new): PineIndicatorDefinition is saved independently of PineIndicatorInstance(instanceId, inputs). PineIndicatorInstances manages multiple copies of one definition; each owns its runtime, named series, input overrides and future persistent-state storage. Removing an instance does not delete the saved definition; input overrides do not leak.
4. **flutter_app/lib/chart/chart_indicator_engine.dart**: Pine chart output calls the bounded streaming executor; existing native built-ins, output model, chart cache, and Replay prefix selection preserved.
5. **flutter_app/test/pine_stage1_runtime_test.dart** (new): eight regression tests cover independent copies, NA arithmetic/comparison/history, deterministic parity with legacy TA, budget failures and Replay cutoff/rewind/source read guards. A follow-up adds assertions for read-only per-instance named-series inspection.
6. **.github/workflows/verify-flutter-range.yml**: includes the new Stage 1 test file with the existing mandatory chart, Range, Replay and paper-trading tests. No APK jobs triggered.
7. **docs/PINE_STAGE1_HANDOFF_2026-11-23.md**: this report.

## B. Replay actual classification

**WORKS for implemented numeric Pine subset:** chart_screen.dart _displayCandles uses _replayPrefixCache.resolve(source, _visibleThrough). Test supplies an observed historical source and proves read indexes are strictly less than cutoff at 3/5/3, results after rewind equal fresh evaluation and persistent state is reset. Bounded numerical programs operate only on available verified bars. Invalidation on rebuilt prefixes is tested.

**PARTIAL for full Pine v6:** parser does not accept var, varip, loops, user functions, request.security, arbitrary type qualifiers, boolean expression grammar or realtime intrabar updates. There are no real v6 rollback/commit snapshots or request-timeframe semantics. These remain Phase 2+; do NOT claim full replay parity for not-yet-implemented language constructs.

**Not broken by these tests:** existing Range, live quote, chart drawing, account and results regression tests passed in the CI run below, but this does not prove a live Android device test.

## C. CI log, exact evidence and limits

First complete run: https://github.com/775878805Osamaha/TradeLab/actions/runs/45213669268
- **status: completed / success** on source commit 06ef92aefbf8e56ced98a96aa75b6532bd4ed229.
- Real GitHub log totals: **938** passing tests in main Flutter suite, **four** independently executed drawing tests, **11** Yemen-timezone price scale tests. Total **953 passed / 0 failed**. Flutter analyzer step success.
- All eight tests in pine_stage1_runtime_test.dart are individually marked PASS in the main test output.
- Later source commits add public read-only named-series inspection. Recheck PR #642 latest HEAD and its own workflow before merge; no assumption that the first green run covers subsequent source changes.
- The local container had git but **no flutter or dart executable**, so local Flutter analyze/test was **not run**. No real Android hardware/emulator, broker feed, benchmark, screenshot-golden baseline or APK checked.
- Existing full test workflow intentionally skips optional drawing goldens with missing reference PNGs and runs specific reliable catalog checks instead. Do not mislabel absent baselines as passed.

## D. Acceptance status and remaining risks

| Requested property | Status |
|---|---|
| Two same-definition instances with separate input values, TA state and runtime IDs | Implemented and tested in core runtime registry |
| Saved definition survives removal of active copy | Implemented and tested |
| Explicit numeric NA / v6 boolean comparison / missing history | Implemented and tested in value/series model; **not** a full v6 comparison parser |
| Step-by-step repeatable evaluation with bounded memory/time/work | Implemented and tested for existing AST subset |
| Budget failure throws clean typed exception | Implemented and tested |
| Replay progress/rewind identical to fresh prefix, no future reads | Implemented and tested for current numeric subset |
| Existing full Pine/Replay/Range/paper regression suite | 953 passed in first CI; latest-run revalidation required |
| User-facing duplicate-instance indicator list/saved state migrations | **NOT IMPLEMENTED**; existing activeIds UI still definition keyed |
| Arbitrary v6 syntax, realtime var/varip, type/qualifier checks | **NOT IMPLEMENTED** |
| Non-blocking Android compute | **PARTIAL**; cooperative deadline only, no cancellable isolate yet |

**Important:** This Stage 1 delivers the independent *runtime foundation*, not the complete user-facing duplicate-instance UI (reserved for indicator-manager integration) or full Pine v6. The current chart computes supported scripts synchronously. A cooperative timeout bounds instruction work but does not guarantee zero UI stutter; Stage 8 must isolate/cancel expensive runs. Inputs and history data in current source remain verified, never fabricated.

## E. Handoff, PR and next task

- PR https://github.com/775878805Osamaha/TradeLab/pull/642 remains **draft / unmerged**, against the user-approved Flutter integration branch. Latest source commit before report was 4b6b58558a5e904474ff28aa69af8b683302e00b.
- No edits to Kotlin main, cTrader credentials, local paper ledger/results, Range builder or unrelated OMEX/ERP projects. No APK or Release.
- Next suggested stage (separate PR after review): **Stage 2 lexical/semantic analyzer** with line-and-column diagnostics, typed qualifiers, if/switch/for/while, functions, and accurate var/varip historical/realtime update semantics. Retain runtime budgets, AST compatibility, Replay no-future invariant and numerical differential tests.
- Future path to main, **proposal only**: preserve Kotlin app initially; audit Flutter Android host, callbacks and persistence; after explicit user approval, create a separate integration PR targeting main, containing tested Flutter app/host without blindly merging all experimental branches; run both Kotlin and Flutter CI and Android side-by-side tests; decide eventual primary app and migration strategy with explicit approval. **Nothing has been merged or moved into main here.**

Resume: start from this report, read current PR #642 and exact latest CI HEAD, do not trust old CI for a newer commit. Keep branch unmerged until the user's review.
