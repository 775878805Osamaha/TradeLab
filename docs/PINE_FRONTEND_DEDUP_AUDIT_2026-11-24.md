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
