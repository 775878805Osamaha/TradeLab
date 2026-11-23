# TradeLab — Pine Script v6 Step 0 Repository Audit (2026-11-23)

> **Status: code/CI evidence audit; documentation-only change. No runtime code changed. No APK created, no merge performed.**
> **Source snapshot:** \`test/flutter-all-fixes-20261116\` at \`6f7cd68fe4322ec0161e7b690d08a00814be57e1\`.
> **Scope:** general Pine indicator engine, chart indicator library/panes and Replay only. User-excluded custom indicator **V10 is out of scope** for development, architecture and acceptance tests.

## 1. Branch and application determination — inspected, not inferred from README

- GitHub repository: https://github.com/775878805Osamaha/TradeLab
- Repository default branch: \`main\`, HEAD \`b4ddfa6846418d30b4ba444cb6ccba210a9a1ebc\` (GitHub branch endpoint). Its \`README.md\`, root \`build.gradle.kts\` and \`app/\` identify the original Kotlin/Jetpack Compose app.
- \`flutter_app/pubspec.yaml\`, \`flutter_app/lib/\`, \`flutter_app/test/\` and \`.github/workflows/verify-flutter-range.yml\` identify a separately maintained Flutter/Dart implementation.
- The **active integration branch for the general Pine work**, established by recent merged PR bases, actual source and latest successful CI, is \`test/flutter-all-fixes-20261116\`. Its HEAD at audit was \`6f7cd68fe4322ec0161e7b690d08a00814be57e1\`. This is **not** a claim that the published Kotlin app or every Android release uses this branch.
- [PR #204](https://github.com/775878805Osamaha/TradeLab/pull/204), head \`feat/replay-risk-reliability-post203\`, was merged to \`main\` on **2026-10-23**; it is not the current Pine branch.
- [PR #637](https://github.com/775878805Osamaha/TradeLab/pull/637), [#638](https://github.com/775878805Osamaha/TradeLab/pull/638), [#639](https://github.com/775878805Osamaha/TradeLab/pull/639), [#640](https://github.com/775878805Osamaha/TradeLab/pull/640) all merged into the Flutter integration branch on **2026-11-23**. #640 merge SHA: \`01ddb4eee720f073b0cc1ff5c24eec0fd46189a5\`. Latest integration HEAD includes follow-up documentation.
- GitHub PR search returned **25 open PRs** during this audit, not the supplied older count of 17. No currently open PR in that result was titled as a new Pine implementation. The **25 most recently updated closed PRs** were reviewed at metadata level; all historical closed PRs were **not** exhaustively inspected. Open PRs include older Range, gestures and Flutter execution changes that must be considered for future conflict checks.

## 2. Directly inspected source and test evidence

| Area | Actual files inspected | Status |
|---|---|---|
| Source grammar / AST / evaluator | \`flutter_app/lib/chart/pine_subset_program.dart\` | **Implemented and previously CI-tested as a strict numeric subset; full Pine v6 not implemented** |
| Indicator output / series cache | \`flutter_app/lib/chart/chart_indicator_engine.dart\` | **Implemented and previously CI-tested for a bounded built-in/subset set** |
| Saved source / library state | \`flutter_app/lib/chart/chart_indicator_library.dart\` | **Implemented and previously CI-tested; one active entry per definition ID** |
| Indicator library UI | \`flutter_app/lib/chart/chart_indicator_library_sheet.dart\` | **Implemented and previously widget-tested (search, saved scripts, favorites, active state)** |
| Study panes | \`flutter_app/lib/chart/chart_indicator_pane.dart\` | **Implemented and previously widget-tested for independent scales, move/resize/remove** |
| Main chart integration | \`flutter_app/lib/screens/chart_screen.dart\` | **Inspected relevant display-prefix/indicator integration; complete 7k-line implementation not exhaustively audited** |
| Replay data cut-off | \`flutter_app/lib/chart/candle_prefix.dart\`; \`flutter_app/lib/replay/\`; chart \`_displayCandles\` and \`_visibleThrough\` | **Prefix isolation implemented; prior regression tests exist. Full mutable runtime/checkpoint semantics not implemented for arbitrary Pine** |
| Core market data / Range | \`flutter_app/lib/data/\` listing, \`flutter_app/lib/data/range_bar_builder.dart\` identified, CI suite coverage checked | **Existing functionality, not modified; full source semantics and live broker equivalence not verified in this audit** |
| Trading/results | \`flutter_app/lib/paper/\`, \`flutter_app/lib/replay/replay_training_session.dart\`, \`flutter_app/lib/screens/results_screen.dart\` identified | **Not exhaustively inspected; must preserve regression coverage** |
| Docs / handoff | \`docs/HANDOFF.md\`, \`docs/CHANGE_REPORTS.md\`, \`docs/TRADINGVIEW_PARITY_ACCEPTANCE.md\` | **Existing handoff verified; this audit adds a separate checkpoint** |
| Native Kotlin | root README, \`app/\`, Gradle files | **Existing separate implementation; not audited as target for this Pine change** |

### Verified subset behavior
- \`PineSubsetProgram\` parses a restricted expression AST with nodes for numbers, names, name-history, unary/binary operations and calls, then evaluates whole \`List<double?>\` series. It is **not** a complete lexer/parser/type-checker for Pine v6.
- Supported code is structured as \`indicator(...)\`, numeric assignments, \`input.int/float\` defaults, source fields \`open/high/low/close/hl2/hlc3/ohlc4\`, \`x[n]\` where supported and \`plot(...)\`. Numeric operations are \`+ - * /\`.
- Supported named calculations found in code: \`ta.sma\`, \`ta.ema\`, \`ta.rsi\`, \`ta.roc\`, \`ta.highest\`, \`ta.lowest\`, \`ta.change\`, \`math.abs\`, \`math.min\`, \`math.max\`, and \`nz\`.
- Up to **8 plots per script** with bounded titles, fixed color constants, linewidth and line/histogram/column style. Multi-plot output is carried through \`ChartIndicatorOutput\`.
- Compile bounds observed: source up to **15,000 characters**, history offset up to **5,000**, at most **16 declared values**, at most **8 plots**, expression depth/token/argument checks. \`null\` is used for unavailable numeric series values. Division by zero returns unavailable instead of fabricated values.
- Code explicitly rejects unsupported \`if\`/loop blocks, \`:=\`, user functions, \`strategy\`, \`request.security\`, \`plotshape\`, unsupported plot options and unknown identifiers.
- \`PineSubsetException\` exposes a **line number** and message, **not a column**. The AST and validation cover arithmetic numeric expressions, **not** Pine's \`const/input/simple/series\` qualifier system or all \`int/float/bool/string/color\` typing.
- \`PineSubsetProgram.evaluate\` constructs complete per-symbol/per-expression series arrays. It is **not** a resumable single-bar interpreter with \`var/varip\`, realtime tick rollback/commit, checkpoints or guaranteed instruction/time/memory execution budgets. Static compile bounds do **not** prove safe runtime resource limits.
- \`ChartIndicatorSeriesCache\` caches outputs using source list identity, length, indicator ID, type, period, source and overlay. **Risk to investigate**, not a proven bug: same-identity/same-length in-place candle changes may not invalidate cached values. Evaluating all history on a cache miss is synchronous on this path; no general-purpose background Pine execution was observed.
- \`ChartIndicatorLibraryState\` retains saved sources separately from \`activeIds\`; removal of an active item can preserve the source. Supports up to **25 saved scripts** and **8 active indicators**; no more than **2 separate study panes** can be active in the current library selection logic. Multiple independent instances of **the same** indicator are **not supported** by the Set-of-IDs data model. Pane order/heights persisted, min/max 84–192 px; no demonstrated collapsible panel or true multi-indicator-per-pane assignment model.
- \`ChartIndicatorPane\` renders independent scales on synchronized source indexes and has up/down/resize/remove controls. Native built-ins in \`ChartIndicatorEngine\` include SMA, EMA, Bollinger Bands, RSI, MACD, ATR, Stochastic and ROC, calculated from source candle data; **the built-in catalog is not evidence that corresponding arbitrary Pine source syntax is fully implemented**.
- Chart \`_displayCandles\` uses \`_replayPrefixCache.resolve(..., _visibleThrough)\`; indicator history and replay-prefix tests assert no hidden-future reads. The current subset recalculates an available prefix; **deterministic reconstruction of stateful user Pine after rewinds is not supported yet**, since that Pine state model does not yet exist.

## 3. Support matrix (current integration branch)

Legend: **Implemented + prior CI success**, **Partial**, **Not implemented**, **Not verified**. CI success describes a workflow against previous or current branch commits, **not** a new local test in this audit.

| Requested capability | Classification | Evidence/gap |
|---|---|---|
| Restricted AST numeric parser and series calculations | Implemented + prior CI success | \`pine_subset_program.dart\`, \`test/pine_subset_program_test.dart\`, CI #45206147704 |
| Numeric \`na\` / historical \`x[n]\` / no-future prefix | Implemented + prior CI success (subset only) | Numeric \`double?\` series, \`CandlePrefix\` tests |
| \`plot\` multi-series, fixed styles | Implemented + prior CI success (subset only) | Up to eight plots, fixed color/width/style |
| Basic source-level error messages | Partial | Line only; column/semantic category absent |
| Full v6 lexer/AST, semantic analysis, type qualifiers | Not implemented | No full bool/string/color/type qualifiers |
| \`if/switch/for/while\`, user functions, \`var/varip\` | Not implemented | Explicit rejected syntax |
| Realtime Pine rollback/commit / per-bar persistent runtime | Not implemented | Bulk series evaluator, no general Pine state machine |
| \`ta.* / math.*\` namespaces | Partial | Verified finite function set only; no support registry by function/overload |
| \`array.* / color.* / str.* / timeframe.*\` namespaces | Not implemented as general Pine APIs | Fixed color constants only |
| \`input.*\` | Partial | Numeric \`input.int/float\` defaults, no general interactive typed input binding |
| \`request.*\` and timeframe no-lookahead semantics | Not implemented | Explicit rejection |
| \`plotshape/plotchar/plotarrow/plotbar/plotcandle/hline/fill/bgcolor/barcolor\` | Not implemented in general Pine compiler | Only current \`plot\` subset |
| Built-in SMA/EMA/RSI/MACD/BB/ATR/Stoch/ROC | Implemented + prior CI success | \`chart_indicator_engine.dart\`, matching engine tests |
| Indicator library, search, favorites, saved custom source | Implemented + prior CI success | State, sheet, widget tests |
| Multiple different active indicators and own-pane plots | Implemented + prior CI success, bounded | 8 active, 2 panes maximum |
| Same indicator multiple independent instances/settings | Not implemented | Active set keyed by unique definition ID |
| Ordering and resizing study panes | Implemented + prior CI success | State and pane/widget tests |
| Collapse, move overlay between panes, arbitrary pane grouping | Not implemented or not verified | No general PaneLayoutModel observed |
| Per-instance layout/compile/run error isolation and resource budgets | Not implemented | Only limited compile bounds and safe unsupported-code rejection |
| Replay indicator prefix isolation | Implemented + prior CI success (subset only) | \`CandlePrefix\` and Pine tests |
| Replay rollback/checkpoint for stateful Pine | Not implemented | Stateful runtime absent |
| Cached re-render when same source snapshot unchanged | Implemented + prior CI success | Cache + 120k source test |
| Incremental per-bar evaluation / background execution / cancellation | Not implemented for general Pine | Bulk series evaluation, synchronous path |
| TradingView numerical fixtures and v6 parity suite | Partial / not verified | Local formula fixtures; external reference parity not established for every function |
| Screenshot goldens with checked-in baselines / Android device benchmarks | Not verified | CI workflow explicitly excludes missing-baseline goldens; no device FPS evidence |

## 4. CI and test verification (read-only)

- [Pine PR #640 CI #45206147704](https://github.com/775878805Osamaha/TradeLab/actions/runs/45206147704): **completed/success**, head \`1aa81b618c27ba1e83a3f7deb249a08ea75638e5\`; reviewed GitHub job steps: dependencies, Flutter analyze, historical/chart/replay suite, four targeted drawing-catalog cases and Yemen timezone step all **success**.
- [Earlier #640 CI #45205126997](https://github.com/775878805Osamaha/TradeLab/actions/runs/45205126997): **completed/failure** on older head \`ad8ec78e35d272d2a793c67c19a8ae4d459c9066\`; docs attribute failure to a stale test, fixed before final green CI. Failure remains recorded.
- [Integration branch CI #45207140674](https://github.com/775878805Osamaha/TradeLab/actions/runs/45207140674): **completed/success**, head \`6f7cd68fe4322ec0161e7b690d08a00814be57e1\`, all listed job steps **success**.
- The intermediate CI #45206908099 was **cancelled**, consistent with a superseding commit; a cancellation is not a pass.
- \`docs/CHANGE_REPORTS.md\` records **930** core tests plus **11** catalog/drawing tests in the #640 run. Here the **workflow/job status was independently checked**; individual test totals were taken from project documentation rather than independently recounted from the test runner log.
- \`.github/workflows/verify-flutter-range.yml\` triggers on relevant Flutter changes/PRs targeting \`main\` or the integration branch; it does **not** run on a documentation-only change. The \`quick-flutter-tests.yml\` workflow is manual; build-APK workflows exist but **were not triggered**.
- **No tests were initiated by this audit.** The current connected environment has \`git\` but no \`flutter\` or \`dart\` executable; there are no new local test results. No emulator, real Android test, live cTrader comparison, benchmark, golden baseline or APK build was performed.

## 5. Architecture decisions / comparison with the requested target

**Keep and extend** \`pine_subset_program.dart\`'s current bounded AST and \`chart_indicator_engine.dart\`'s tested built-ins; do not replace working source math blindly. Build a separately testable general runtime/evaluator boundary before widening the grammar.

Required next architecture boundaries (proposed, **not implemented**):
1. Lexer tokens with source spans (line **and column**), parser AST nodes including declarations/control flow and semantic typed IR.
2. Values with explicit typed \`na\` and Pine qualifier lattice \`const < input < simple < series\`; do not assume current \`double?\` implements the complete semantics.
3. \`CompiledScript\` / isolated per-instance \`ExecutionContext\` with bounded history, step/memory/deadline budgets; deterministic historical bar runs.
4. Realtime update/rollback/commit and \`var/varip\` semantics, with snapshots for Replay seeks **only after** correctness tests on static bar runs.
5. Typed multi-output representation distinct from render styles; plot API restrictions as documented by TradingView; style-only changes must avoid recomputation.
6. Explicit \`SavedIndicatorDefinition\` vs unique \`ActiveIndicatorInstance\` identity, then \`PaneLayoutModel\` supporting multiple instances/layouts.
7. Verified immutable source snapshot/cutoff identity across chart, Replay and calculation cache. Profile before moving expensive computations out of UI isolate.

**Official behavior to implement independently (no closed-source copying):**
- https://www.tradingview.com/pine-script-docs/language/execution-model/ — repeated executions and realtime rollback/commit.
- https://www.tradingview.com/pine-script-docs/language/type-system/ — type qualifiers and value typing.
- https://www.tradingview.com/pine-script-docs/visuals/plots/ — plot signatures and restrictions.
- https://www.tradingview.com/pine-script-docs/visuals/overview/ — plot visual global-scope restrictions.

Do **not** assume arrays, timeframes or advanced drawing visuals can be added before semantic and runtime invariants.

## 6. Risk register and next concrete implementation batch

| Priority | Risk | Required acceptance |
|---|---|---|
| P0 | Bulk eager evaluation of untrusted source without runtime instruction/memory/time budget | Fails closed with bounded execution and deterministic diagnosis; no UI freeze |
| P0 | Stateful future leak when adding mutable Pine state to Replay | Replay prefix forward and rewind/checkpoint = fresh prefix; no hidden bars |
| P0 | Existing live chart/Range/results regressions | Existing \`verify-flutter-range.yml\` passes on implementation PR head before merge |
| P1 | Cache invalidation by identity/length only | Same-object changed-content scenarios or enforce/prove immutable input contract |
| P1 | No real qualifiers/typed \`na\`; only line diagnostic | Typed semantic matrix and exact line/column regression cases |
| P1 | Single active ID prevents independent instances | Independent settings/runtime, remove view without deleting source |
| P2 | Two-pane hard limit and missing general layout | Pane model with synchronized time/crosshair and no price-axis contamination |
| P2 | Unverified TradingView numerical, device and goldens | Published reference fixtures, real-device evidence and stable baselines |

**Next PR (after this audit, not performed here):** Stage 1 safe execution foundation on a fresh branch from the latest integration HEAD. First add independent tests for explicit unavailable values, bounded history, deterministic prefix reruns, resource exhaustion and cache invalidation; implement the minimal runtime/value/budget abstraction necessary to pass; adapt current subset without deleting existing behavior. Run \`flutter analyze\`, targeted tests and full \`verify-flutter-range\` CI on the exact PR head; do not merge before green CI. Keep Replay, Range, paper trading/results and original Kotlin code untouched unless a regression demands a proven fix. **No APK**.

## 7. Audit handoff / what is actually done

- **Performed:** GitHub repository metadata, branches, source files, test files, active workflows, PR #204/#637–#640, 25 open PR records, 25 recent closed PR metadata, reports in \`docs/\` and recent CI run/job checks. Architecture compared with observed source.
- **Not performed:** code implementation of stages 1–9, local Flutter commands, live brokerage/session tests, Android tests, benchmarks, APK creation, merge to development or \`main\`.
- **Committed file(s) in this audit:** this \`docs/PINE_V6_STEP0_AUDIT_2026-11-23.md\` report only.
- **Audit branch:** \`audit/pine-v6-step0-20261123\`, based on development SHA \`6f7cd68fe4322ec0161e7b690d08a00814be57e1\`. PR/commit URLs will be available from GitHub after the branch write.
- **Continuation:** Re-fetch integration HEAD and open PRs; use this verified audit as the starting point. Next execute Stage 1, then later grammar/semantics, plot API, instances/panes, stateful Replay, performance and parity in test-gated batches.
