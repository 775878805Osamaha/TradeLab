# Pine frontend deduplication — audit before removal (2026-11-24)

Base: Stage 3a PR #645, rebased head `2f1328ded6fc456566cf84df5f930b2d2d0cf9e3`. This independent change set temporarily targets the #645 source branch so only cleanup changes are reviewed; retarget to integration only after owner merges #645. No file, old test or compatibility API is deleted. Stage 3b remains blocked.

## Evidence so far
- `flutter_app/lib/chart/chart_indicator_library.dart`: imports both frontends. `_compileSeries` and `compileError` use `PineV6Frontend.prepare`; Stage 3a uses `PineV6LanguageProgram.compile`. The alternative import supplies the public getter `ChartSavedIndicatorScript.frontendAnalysis => PineFrontend.analyze(source)` only within this inspected file.
- `pine_frontend.dart` imports/exports its AST, lexer, parser, semantic analyzer; its executable is the same legacy `PineSubsetProgram`, not an independent market-data executor.
- `pine_frontend_v6_test.dart` exercises all old components and getter. Both CI workflows include the compatibility test.
- Repository default-branch search is not evidence about this integration branch. The new CI step prints exact-commit git grep over all Flutter lib/test files for old imports/types/calls/getter. Inspect that log before claiming no production consumers or registrations. Any discovered external consumer blocks removal.
- Canonical frontend already covers lexical/source locations, indentation, multiline strings, resource limits, syntax recovery, var/varip AST, conditions, local plots, type/qualifier/name resolution, UDF recursion, and duplicate declarations. Stage 3a already ports direct na comparisons and EMA/RSI length rules. Duplicate parameters already use canonical _define duplicate-name guard.
- Two useful gaps: old analyzer explicitly rejects parameter reassignment; canonical did not mark parameter symbols. Old history index rule aims to reject future indices; canonical checked int type only (runtime also bounds indices). This PR ports immutable parameter guard and explicitly rejects negative integer literal AST offsets at compile time; tests verify both. Full coverage of dynamic history offsets stays under runtime guards.
- Compare old frontend, canonical frontend, and direct numeric executor for seven old fixtures including plot style, metadata and full bar series. Existing canonical and compatibility tests stay intact. No parity is claimed before CI.

## Disposition (proposed only)
| Path | Proposed action after gates | Reason |
|---|---|---|
| pine_frontend.dart | Remove only after exact-ref caller audit and compatibility getter migration | duplicate entrypoint |
| pine_frontend_ast.dart | Remove only with old parser | duplicate AST; canonical pine_v6_ast.dart stays |
| pine_frontend_lexer.dart | Remove only after lexical fixture migration | canonical lexer stays |
| pine_frontend_parser.dart | Remove only after structure and recovery parity | canonical parser stays |
| pine_frontend_semantic.dart | Remove only after semantic rules and diagnostic parity are reviewed | canonical analyzer stays; two candidate safeguards ported |
| pine_frontend_v6_test.dart | Migrate all 16 cases or demonstrate equivalent canonical coverage; keep until green | retain regression evidence, including Stage 2 analysis-only contract |
| ChartSavedIndicatorScript.frontendAnalysis | replace/remove only after caller scan and public API review | currently a concrete reference |
| pine_v6_*.dart, pine_subset_program.dart, pine_runtime_core.dart, pine_indicator_instance.dart | keep | canonical analyzer, legacy and Stage 3a runtime, Replay safeguards |
| CI workflows | keep both test suites until removal is approved | full regression + differential gate |

## Acceptance
1. #645 is green and owner merges it.
2. Exact-ref grep is reviewed, including all external callers, registration sites and test imports; no hidden real-runtime use.
3. Full no-APK CI and differential suite green; no unsupported script silently becomes executable; every migrated old fixture stays covered.
4. Only then propose deletion/migration of old files in this cleanup PR, rerun full CI on final head and wait for owner merge. No Stage 3b until owner confirms both merges.

## Verified CI and owner merge (2026-11-24)
- #645 exact source `2f1328ded6fc456566cf84df5f930b2d2d0cf9e3`: [CI 45289231566](https://github.com/775878805Osamaha/TradeLab/actions/runs/45289231566), 998+4+11 = **1013 PASS / 0 FAIL**. #645 merged by owner at `e34de3266a96f0031e5f1c8d1ce5f9c3d511f81c`; integration merge tree is identical to the tested #645 source tree. [Integration CI 45290171333](https://github.com/775878805Osamaha/TradeLab/actions/runs/45290171333) was running when checked.
- #646 original exact source `8870700b1e62d040c8b255723afd8698c3443229`: [CI 45289405492](https://github.com/775878805Osamaha/TradeLab/actions/runs/45289405492), 1001+4+11 = **1016 PASS / 0 FAIL**. All 16 compatibility cases, 27 canonical frontend cases, and 3 differential/guard cases pass. The differential test loops through all seven fixtures and asserts values and metadata against the legacy executor; all seven passed (one test case, not seven additional counts). Both analysis steps succeed with nonfatal infos.
- The first automated grep had over-escaped regex dots and used `|| true`, so it did not prove absence of imports; output nevertheless found the production compatibility getter at chart_indicator_library.dart:153 and test calls at lines 209–210. Corrected grep in this follow-up, preserve both parsers. **No removal in #646**, even if the corrected scan finds no additional consumers.
- #646 is a documentation/semantic-port/differential-only PR. Propose a separate later removal PR only after all three owner gates are proven; keep old tests and API until then. Stage 3b remains blocked until owner explicitly confirms #645 and #646 merged.

## Old 16-test traceability (all remain and passed)
This is a coverage inventory, not authorization to drop any test. Similar canonical tests are named by subject; exact fixture equivalence and diagnostic differences must be checked in a future removal PR.

| # | Old case | Canonical evidence / remaining requirement |
|---|---|---|
| 1 | Lexer indentation, comments, color, operators | Existing lexer location/color fixture; exact >= and comment exclusion assertions to compare |
| 2 | Wrapped lines and triple strings | Existing continuation and triple-quote lexer fixtures; exact combined fixture remains |
| 3 | var/varip, reassignment, history, named argument AST | Existing typed AST and named arguments cases; compare snapshot contract |
| 4 | Functions, if/else, for/while, switch, ternary | Existing flow and ternary AST tests; exact combined fixture remains |
| 5 | Global-only visuals | Existing local plot/plotshape case; verify global plotshape acceptance and column |
| 6 | Multiple semantic errors with spans | Existing undefined-name, redeclaration/type, qualifier and location tests; exact multi-error fixture remains |
| 7 | Local scope escape | Existing scope-local variable escape test; compare exact line |
| 8 | History index, untyped na, undeclared assignment, recursion | New negative-history guard; existing semantic checks; exact combined canonical fixture still needed |
| 9 | Syntax recovery | Existing two parser error locations; exact malformed assignment fixture remains |
| 10 | Huge input and zero deadline | Existing source and cooperative deadline tests; check differing limits and exact original threshold |
| 11 | Saved-script control flow and compatibility getter | Stage 3a runtime/chart tests; old getter assertion must be migrated or explicitly retired after API review |
| 12 | Numeric conditions/logical operands rejected | Canonical condition/logical diagnostics exist; explicit combined fixture with four errors still needed |
| 13 | Explicit bool conversion accepted | Canonical bool conversion support requires exact fixture verification; keep old test |
| 14 | Direct na comparisons | Ported canonical test passes |
| 15 | EMA/RSI simple-int qualifier | Ported canonical test passes |
| 16 | Seven numeric differential fixtures | New cross-frontend differential test passes all seven; keep until a canonical-only test retains all fixtures and metadata assertions |

Owner gates: (a) differential PASS on original tested SHA; (b) NOT established, getter remains and scan required correction; (c) inventory documented but full migration/approved retirement NOT established. No deletions. Re-run full CI after this audit fix and retarget to integration.
