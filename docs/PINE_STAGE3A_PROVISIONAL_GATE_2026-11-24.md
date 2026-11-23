# TradeLab — Stage 3A provisional branch and dependency gate (2026-11-24)

> **Not an implemented Stage 3 runtime.** Branch `feat/pine-stage3a-runtime-provisional-20261124` was created from Stage 2 PR #643 HEAD `a8f7db3e99123489771d260727a839c1e4e7e2a9` on 2026-11-24. The owner has not yet selected #643 or #644 and specifically required that Stage 3 runtime implementation wait for their decision. This provisional branch carries only additional **pre-Stage-3 verification tests and CI settings**, with no new var/varip/control-flow/UDF runtime code, no APK, no PR, and no merge. Keep #642, #643 and #644 untouched and unmerged.

## 1. Verified decision evidence

- PR #643: created under GitHub login `775878805Osamaha`, opened 2026-11-23T16:46:04Z. Stacked on Stage 1 #642. 13 files, 2225 additions, 9 deletions, 39 commits, 25 frontend tests. Exact tested source `f135bf4119512777eea643fb72eca8010992454e`: [CI #45230338091](https://github.com/775878805Osamaha/TradeLab/actions/runs/45230338091) **978 passed, 0 failed** (963 + 4 + 11), Flutter analyze success.
- PR #644: same recorded GitHub login, opened 2026-11-23T16:50:18Z. Also stacked on #642. 12 files, 2048 additions, 8 deletions, 28 commits, 16 frontend tests. [CI #45224969067](https://github.com/775878805Osamaha/TradeLab/actions/runs/45224969067) **969 passed, 0 failed** (954 + 4 + 11), Flutter analyze success. GitHub author login is not reliable evidence of which human or assistant session initiated it.
- Both update `flutter_app/lib/chart/chart_indicator_library.dart`, `.github/workflows/verify-flutter-range.yml`, `docs/HANDOFF.md`, `docs/CHANGE_REPORTS.md`, `docs/PINE_STAGE2_HANDOFF_2026-11-23.md`. Distinct frontend AST, lexer, parser, semantic and test filenames contain competing implementations. **Never merge both**. Recommended primary review is #643 (larger test corpus and newer semantic checks), selectively port #644 v6 bool casting, direct-na-comparison, and ta EMA/RSI simple-length checks after separate tests and official-doc verification.
- Nothing was merged. The owner retains the final decision. A quality comparison, not a user approval, is not enough to authorize Stage 3 runtime activation.

## 2. Positive differential checks and negative mutation checks

Existing Stage 2 PR #643 test `flutter_app/test/pine_v6_frontend_test.dart` includes a numerical differential gate across **five representative source programs**, comparing the former `PineSubsetProgram.compile().evaluate(...)` outputs against `PineV6Frontend.prepare().evaluateSupported(...)` by plot, values and metadata. CI #45230338091 includes that passing test. This is **not** exhaustive proof for all possible valid numeric programs.

For further coverage, this provisional branch adds `flutter_app/test/pine_differential_matrix_test.dart` with **169 generated supported-script examples** in three tests: 147 ta family × source × period combinations; 16 arithmetic/math/history/input variants; 6 plot-format checks. Every generated program must compile by the existing compiler, be accepted as executable by the v6 frontend gate, and reproduce **exact** old numeric and plot-metadata output for 96 real deterministic OHLC bar values. The existing full Flutter workflow and the provisional no-APK workflow include the test. Record CI outcome after the run; do not infer it from compilation alone.

Real intentional-mutation CI proof on isolated *no-PR* branches:
- [Replay future leak #45217673219](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217673219): expected failure, **7 passed / 1 failed**; instrumented source reads [0,1,2,3] where index 3 was hidden and only indices below 3 allowed.
- [Shared persistent state #45217676913](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217676913): expected failure, **7 passed / 1 failed**; the second instance had `counter=4.0` instead of an empty state.
- Independent complete-suite mutation logs also confirmed: [#45217685758](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217685758) and [#45218410206](https://github.com/775878805Osamaha/TradeLab/actions/runs/45218410206), each intentionally 937 passing / one failure. The temporary mutation branch was reset to the clean Stage 1 HEAD; no mutant entered any PR.

## 3. Official Pine v6 execution-model decisions for later Stage 3A

- **Historical/replay bars:** treat each available Replay candle as **already confirmed/closed**, evaluated once in strict historical order. A `varip` declaration behaves like a `var` for such runs because there are no intrabar updates. **Do not claim realtime intrabar varip support** without a separate tick-aware rollback/commit engine. References: https://www.tradingview.com/pine-script-docs/language/execution-model/ and https://www.tradingview.com/pine-script-docs/language/variable-declarations/.
- **`var` initialization timing:** initialize once the *first time execution reaches its declaration*, which may be on a later candle in a conditional local block; not automatically every global variable at the first bar. Regular declarations (without `var`) re-evaluate upon execution on each bar. Reference: https://www.tradingview.com/pine-script-docs/language/variable-declarations/.
- **User-defined function call-site scope:** every written call has independent locals, expression history, and `ta.*` accumulator state. A conditional call advances its own history **only when executed**, potentially creating inconsistent history; warn/track it, never silently process skipped bars. Reference: https://www.tradingview.com/pine-script-docs/language/user-defined-functions/ and https://www.tradingview.com/pine-script-docs/errors/CW10003/. Pine v6 forbids recursive UDF calls; the semantic pass must detect direct and indirect recursion before runtime.
- **Loops:** Pine v6 provides `for`, `while`, and `for...in`. Both `break` and `continue` are legal inside loops. Implement a per-loop cap *and* the Stage 1 shared instruction/storage/deadline budgets; infinite loops throw a typed error rather than blocking indefinitely. `for...in` depends on array iteration and can be explicitly deferred to Stage 3B if the array subset is not ready. Reference: https://www.tradingview.com/pine-script-docs/language/loops/.
- **Expressions as blocks:** v6 `if`, `switch`, and loops can return values from a last expression; inspect Stage 2 AST/parser and extend these before activating the runtime. No semantic guessing or fake values.
- **Replay rewind:** use fresh prefix evaluation up to the verified visible candle, reinitialize all per-instance and per-call-site state; this is bounded by O(visible bars × executed AST steps) and stores bounded history. Only optimize with checkpoints after equality/no-future tests.
- **Isolation and security:** each `PineIndicatorInstance` owns its vars, call scopes, plots and budgets. No shared mutable script state. User code runs in a closed AST interpreter, not via Dart eval or a native plugin. Errors are typed and resource-bounded.

## 4. Mandatory next Stage 3A tests **after owner's canonical PR selection**

- `var` / `varip` historical 50-bar hand-calculated counters, once-only local initialization, no shared state.
- `:=`, `if` and `switch` as both value and statement/blocks.
- Sum over `close[i]` with `na` warmup, for/while break/continue and per-loop exhaustion error.
- UDF call-site-local `ta.sma` state with conditional call history (and diagnostic).
- Two running instances from same saved definition, independent `var` values and settings.
- Replay 50→20→30 equality with direct prefix 20/30 and no future read; separate session state.
- **New deliberate mutation** on an isolated no-PR branch: make `var` state shared, prove relevant test fails, revert.
- All Stage 1 and 2 tests, Range/Replay/paper/visual regression and true no-APK CI counts on exact new-code SHA.

**No Stage 3A execution support, new phase 3 PR, new UI, merging, APK, or unrelated project work has been performed in this provisional branch.** The owner must choose #643 or #644 before implementing a new 3A runtime.
