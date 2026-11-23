# TradeLab — Stage 2 Pine v6 Frontend Handoff (2026-11-23)

> **Working branch:** feat/pine-stage2-frontend-v6-20261123  
> **Draft PR:** https://github.com/775878805Osamaha/TradeLab/pull/644  
> **Base:** feat/pine-stage1-instance-safe-runtime-20261123 at ef917ad2c3dd3dc3e036e17b9dc1ead2d59631ee — PR #642 is still awaiting the owner's merge into test/flutter-all-fixes-20261116.  
> **Merge policy:** Neither PR #644 nor #642 was merged by the assistant. Absolutely no main/Kotlin/APK or other projects changed.

## First requirement: mutation tests BEFORE Stage 2 source edits

Two controlled regressions were introduced on the isolated branch test/pine-mutation-isolation-no-pr-20261123 (never opened a PR), with temporary push-only CI verification:
1. **Replay future bar:** deliberately changed rebuild loop to include index equal to visibleCount, thereby reading unrevealed source. [Actions #45217685758](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217685758): **failure by design, 937 passed / 1 failed**. The named Stage 1 Replay test asserted source reads less than 3 and reported actual reads [0,1,2,3]. Compiler/analyzer and unrelated tests did not fail.
2. **State sharing:** restored the correct Replay loop and deliberately replaced per-instance persistentState with a static shared map. [Actions #45218410206](https://github.com/775878805Osamaha/TradeLab/actions/runs/45218410206): **failure by design, 937 passed / 1 failed**. The Stage 1 instance-isolation test expected an empty second-instance state and found counter=4.0 from the first.
3. **Cleanup:** reset temporary branch to the unmodified Stage 1 SHA ef917ad2c3dd3dc3e036e17b9dc1ead2d59631ee using a forced-with-lease branch ref update. Mutation commit/run history remains accessible via the CI links. Neither mutant is in Stage 2.

**Conclusion:** each prior test caught its own deliberately injected fault. This proves sensitivity to these specific mutations, NOT universal test completeness.

## Stage 2 actual implementation

| File | Change |
|---|---|
| flutter_app/lib/chart/pine_frontend_ast.dart | Explicit source-spanned diagnostic, token and typed AST nodes for declarations, reassignment, persistence, binary/unary/ternary, calls and named args, historical indexing, if/switch/for/while, function declarations and typed parameters |
| flutter_app/lib/chart/pine_frontend_lexer.dart | Bounded lexical scan with v6 version annotation, whitespace/indent/dedent, multiline wrapping in parentheses and trailing operators, comments, numeric/strings/triple strings/hex colors, operators, resource diagnostics |
| flutter_app/lib/chart/pine_frontend_parser.dart | Indentation-based nested statement parser, Pratt expressions and function params, named arguments, AST serialization/snapshots, bounded recursion, recoverable syntax errors with line/column |
| flutter_app/lib/chart/pine_frontend_semantic.dart | Scoped primitive types int/float/bool/string/color, qualifier lattice const/input/simple/series, scope checking, duplicate/unknown names, incompatible assignment/index/conditions, illegal plot* local calls, function parameter/reassignment rules |
| flutter_app/lib/chart/pine_frontend.dart | Safe frontend route; if the existing PineSubsetProgram compiler supports the source it remains the ONLY executable path. Valid advanced AST without runtime is flagged not executable yet |
| flutter_app/lib/chart/chart_indicator_library.dart | Added frontendAnalysis and new line/column/diagnostic compileError for unsupported saved custom Pine. The existing supportedIndicator execution and numeric AST evaluator remain unchanged |
| flutter_app/test/pine_frontend_v6_test.dart | Unit tests for Lexer, wrapped lines, AST snapshots/control flow, semantic scope/type/errors, resource bounds, safe unsupported scripts, differential numeric output |
| .github/workflows/verify-flutter-range.yml | Added Stage 2 tests to full existing Pine/Replay/Range/Paper CI; enabled safe verification for stacked PR and isolated Stage 2 branch. No APK |
| docs/PINE_V6_STAGE2_LANGUAGE_MATRIX_2026-11-23.md | Feature-by-feature Parsed / Semantics / Executed / Unsupported table; official source links and remaining exclusions |
| docs/PINE_STAGE2_HANDOFF_2026-11-23.md | This checkpoint |

**Non-goals maintained:** no var/varip runtime, no if/switch/for/while evaluation, no user-function invocation, no strategy orders or fictitious market data. The Stage 1 executor and existing numeric AST remain intact. User-excluded V10 was not used.

## Tests and real CI (update after final exact-head run)

- Initial Stage 2 [CI #45221049180](https://github.com/775878805Osamaha/TradeLab/actions/runs/45221049180): **FAILED in flutter analyze** (four nullability errors in Pratt parser, one semantic function missing total return). Corrected in follow-up code commits 22cd486acd6d53def6d96549957b0c0428d3ccd5 and 335c9b4665fb8b0fe8472db1b376e4de55d7e3f3. Do not count that run as passed.
- Pending as of initial report: final exact-head Flutter analyzer, Stage 2 unit tests and all existing Pine/Replay/Range/Paper CI. Until a successful run is verified, the PR must remain draft and unmerged.
- Local Flutter/Dart toolchain **NOT AVAILABLE**, no locally executed tests or device/emulator session. No APK or Releases.
- See final PR body and updated report for the actual outcome and test count.

## Known unsupported areas (no overclaim)

The frontend implements the explicitly requested mainstream statements/expressions but is **NOT** the full TradingView v6 grammar or complete type checker. Unimplemented or partial syntax includes tuple patterns, typed collections/maps/matrices, method declarations, imported libraries, general if/switch returned expressions, full overload resolution, some complex line wrapping and user-defined reference types. It is deliberate to classify unsupported constructs rather than evaluate unsafe fake results. Full runtime semantics belong to Stage 3.

Source references:
- https://www.tradingview.com/pine-script-docs/language/script-structure/
- https://www.tradingview.com/pine-script-docs/language/type-system/
- https://www.tradingview.com/pine-script-docs/language/conditional-structures/
- https://www.tradingview.com/pine-script-docs/language/user-defined-functions/

## Next approved work direction (proposal, NOT executed)

After the user merges #642, compare branch HEADs, retarget/rebase #644 onto test/flutter-all-fixes-20261116 with approval, run full CI again on final PR SHA and merge only by user. Next Stage 3: runtime execution of the validated AST with var/varip persistence and realtime rollback/commit, if/switch/for/while and user functions, independent replay snapshots and strict resource budgets. Keep no-future, numeric parity and safe unsupported fallbacks.
