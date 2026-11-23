# TradeLab Pine v6 — Stage 3a language matrix (2026-11-24)

**Status:** Stage 3a limited language runtime has a verified full-source green CI for the documented subset: [Actions #45283899469](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283899469), code SHA `42d10fbd7a790e7495364e197f9422855d59e2ba`, **982 main + 4 drawing + 11 timezone = 997 passed / 0 failed**, Flutter Analyze PASS. No local Flutter/Android device/APK. Stage 3a is stacked on **PR #643**, which is stacked on **PR #642**; PR #644 is an alternative and must not be merged. No merge or APK.

| Feature | Lex / Parse / Semantic | Stage 3a runtime status | Conditions and exclusions |
|---|---|---|---|
| Numerical legacy SMA/EMA/RSI/ROC/highest/lowest/change and math/plots | Implemented in prior stages | **Old executor unchanged** | Existing PineSubsetProgram remains the execution path for previously supported numeric source |
| Direct equality/inequality against literal `na` | Rejected in semantic analyzer | Rejected | Ported manually from #644 into #643 semantic architecture; use `na(x)`, not `x == na` |
| `ta.ema` / `ta.rsi` length | Checks int, simple-or-weaker qualifier, positive literal | Old executor only, no new TA library | Ported from #644; other signatures and dynamic length functions not implemented |
| `var` | Parsed and semantic checked | **Implemented in isolated Stage 3a closed-bar engine (CI verified on supported subset)** | Initializes once on first entry into block; keeps state across bars and independent instances |
| `varip` | Parsed and semantic checked | **Implemented for closed bars only (CI verified on supported subset)** | In historical Replay every bar is confirmed. No intrabar ticks, rollback, or realtime varip persistence tested; explicit limit |
| Reassignment `:=`, `+=`, `-=`, `*=`, `/=`, `%=` | Parsed and semantic checked | Implemented for supported numeric subset (CI verified on supported subset) | Scoped local/global bindings |
| `if/else` blocks and ternary | Parsed and semantic checked | Implemented for supported bool/numeric subset (CI verified on supported subset) | Pine v6 requires bool conditions; expressions `x = if ...` are **not parsed** by Stage 2 grammar; not claimed |
| `switch` arms and returned last expression | Parsed and semantic checked | Implemented as statement and function return (CI verified on supported subset) | Expression form `x = switch ...` not supported by parser yet |
| `for/to/by`, `while`, `break/continue` | Parsed and semantic checked | Implemented with finite iteration caps (CI verified on supported subset) | Loop budget + instruction/time/memory budget; `for...in` collections **not implemented** (array/map/matrix library Stage 3b+) |
| User-defined functions | Parsed and semantic checked | Implemented for supported scalar/numeric subset (CI verified on supported subset) | Unique written-call-site var/SMA state; conditional calls only append on actual evaluation. No tuple/array/UDT return or full overloads |
| `ta.sma` inside UDF | Parsed and semantic checked | Implemented per written call site (CI verified on supported subset) | No new extended TA library yet; other functions deferred to 3b |
| Replay rebuild | Stage 1 full-prefix model | Implemented for new language engine (CI verified on supported subset) | Recompute exactly source[0..cutoff); O(cutoff * script work), no future reads, no incremental checkpoint optimization |
| Indicator duplication / independent sessions | Stage 1 registry for legacy | New Stage 3a instances have independent state, no shared static buffers (CI verified on supported subset) | User-facing library UI integration may require a follow-up |
| request.security, external IO, strategies, arbitrary Pine runtime | May parse | **Rejected / not executed** | No artificial values, no lookahead, no expanded builtins |

## Official references consulted

- https://www.tradingview.com/pine-script-docs/language/execution-model/ : historical bars execute once per committed bar; var resumes committed state while varip escapes intrabar rollback on a realtime open bar.
- https://www.tradingview.com/pine-script-docs/language/user-defined-functions/ : each written function call forms an independent scope and history trail; a conditional call can skip some bars.
- https://www.tradingview.com/pine-script-docs/language/loops/ : finite loops and for-in collection behavior; collections excluded for now.
- https://www.tradingview.com/pine-script-docs/language/type-system/ : type/qualifier checks.

## Selective transfer from PR #644

**Taken, manually reimplemented in #643 architecture only:** direct literal-na comparison rejection, type/qualifier/positive-literal checks for EMA/RSI length, two adapted tests in `flutter_app/test/pine_v6_frontend_test.dart`.

**Not taken:** `pine_frontend_*.dart` lexer/parser/AST/semantic, its competing `chart_indicator_library.dart` changes, alternative CI workflow, `docs/HANDOFF.md` overwrite, `docs/CHANGE_REPORTS.md` overwrite or its separate support matrix. No path from PR #644 is imported; the existing #643 files remain authoritative.

## Stage 3a final CI and mutation QA

- Tested 17 Stage 3a language runtime cases with genuine OHLC input: var/varip, two written UDF callsite vars and two SMA callsites, if/else and switch blocks, for/while, break/continue, loop limit, na/history, Replay prefix 50→20→30 no-future, two independent sessions, chart saved scripts and legacy regression, and unsupported calls.
- 2 selectively ported #644 semantic cases also passed (direct na comparison rejection; EMA/RSI length int/simple/positive literal checks).
- [Run #45282914169](https://github.com/775878805Osamaha/TradeLab/actions/runs/45282914169) failed **978 PASS/2 FAIL** due missing Arabic line marker `السطر` in compiler error. Repaired; [final run #45283899469](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283899469) **997 PASS/0 FAIL**.
- Real-Pine var shared-state mutant [#45283643004](https://github.com/775878805Osamaha/TradeLab/actions/runs/45283643004) failed **978 PASS / 2 expected FAIL** (two-instance and Replay session), after nonmutation editor-diagnostic failures were fixed on the isolated temporary branch. Temporary branch restored to clean code; no PR.
- **Not a claim** of universal v6 compatibility: full UDF return/qualifier inference and arbitrary series history, `x = if/switch` grammar, array/map/matrix `for...in`, realtime intrabar `varip`, extended TA library, live-device performance and mobile UI safety remain outside verified scope.
