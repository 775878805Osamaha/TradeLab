# Archival provenance

This is the original alternate Stage 2 handoff from the merge of PR #642. Preserved in full below, while the selected canonical PR #643 report is reinstated at the original path. The corresponding alternate parser source and tests remain in the merged base for compatibility. This archive does NOT mean PR #644 merged as a pull request.

---

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
- **Green code run:** [Actions #45222237585](https://github.com/775878805Osamaha/TradeLab/actions/runs/45222237585), SHA 6523e5c67ba4ed67c2f4947b40fff34f2e9a4b6f, **completed/success**. Job log: **950 main Flutter tests + 4 separately run drawing tests + 11 Yemen scale tests = 965 passed, 0 failed**. All 12 new Pine Stage 2 tests passed; flutter analyze PASS; Phase 1 Pine/Replay/Range/Paper regressions included. A subsequent docs-only PR run [#45222404968](https://github.com/775878805Osamaha/TradeLab/actions/runs/45222404968) also **completed/success** at SHA fb3ae18a01809cd054be8da70801296223e76708. No local Flutter or Android tests. Leave PR draft and unmerged.
- Local Flutter/Dart toolchain **NOT AVAILABLE**, no locally executed tests or device/emulator session. No APK or Releases.
- See final PR body and updated report for the actual outcome and test count.

## Known unsupported areas (no overclaim)

The frontend implements the explicitly requested mainstream statements/expressions but is **NOT** the full TradingView v6 grammar or complete type checker. Unimplemented or partial syntax includes tuple patterns, typed collections/maps/matrices, method declarations, imported libraries, general if/switch returned expressions, full overload resolution, some complex line wrapping and user-defined reference types. It is deliberate to classify unsupported constructs rather than evaluate unsafe fake results. Full runtime semantics belong to Stage 3.

Source references:
- https://www.tradingview.com/pine-script-docs/language/script-structure/
- https://www.tradingview.com/pine-script-docs/language/type-system/
- https://www.tradingview.com/pine-script-docs/language/conditional-structures/
- https://www.tradingview.com/pine-script-docs/language/user-defined-functions/

## Additional v6 semantic validation and last code CI (2026-11-23)

Verified against official Pine v6 language and migration documentation: numeric values are **not** implicitly cast to bool in if/while/ternary/logical conditions; explicit `bool(value)` syntax is parsed/type-checked, but the Stage 2 runtime still rejects advanced control flow. Direct `x == na` or `x != na` is flagged in source analysis (use `na(x)`); stage-1 numeric-value arithmetic/comparison model remains a separate internal API. For the documented simple-int family, `ta.ema` and `ta.rsi` length arguments reject a series-int qualifier, including named `length=` arguments; input-int values remain accepted. Cast calls for int/float/bool/string/color are represented and typed but are **not** independently executed unless the existing bounded interpreter already supports them. Added four regression tests for these cases and extended differential fixtures with `ta.change`, `math.min/max`, `input.float` and plot styles. No market data fabricated.

[GitHub Actions #45224018771](https://github.com/775878805Osamaha/TradeLab/actions/runs/45224018771): **completed / success** on **last production-code SHA e6971be9fc0315d40ffe50dd360ede8c8e29694c**. Real log: **954** tests in main Flutter suite, **4** individually passing drawing cases, **11** Yemen chart-scale tests: **969 passed, 0 failed**. `flutter analyze` PASS, all 16 current Pine Stage 2 test cases PASS. This supersedes the earlier 965-test run for the final code; earlier failed and cancelled runs remain documented above. Local Flutter/Dart, real device, performance benchmarks and APK **not run**. This documentation/CI maintenance commit will have its own exact-head check after upload.

Temporary push-trigger CI has been removed from the workflow because the stacked PR is now checked directly against its allowed Stage 1 target; `workflow_dispatch` remains available. This avoids doubling future CI jobs. PR #644 remains draft/unmerged; no modifications to PR #642 or main.

Official references: https://www.tradingview.com/pine-script-docs/migration-guides/to-pine-version-6/ and https://www.tradingview.com/pine-script-docs/language/type-system/.

## Next approved work direction (proposal, NOT executed)

After the user merges #642, compare branch HEADs, retarget/rebase #644 onto test/flutter-all-fixes-20261116 with approval, run full CI again on final PR SHA and merge only by user. Next Stage 3: runtime execution of the validated AST with var/varip persistence and realtime rollback/commit, if/switch/for/while and user functions, independent replay snapshots and strict resource budgets. Keep no-future, numeric parity and safe unsupported fallbacks.
