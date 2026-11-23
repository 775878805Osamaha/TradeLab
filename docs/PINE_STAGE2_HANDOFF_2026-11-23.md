# TradeLab — Pine v6 Stage 2 frontend handoff (2026-11-23)

## 2026-11-23 continuation — UDF argument semantics and loop-control validation

**Actual source commit tested:** `f135bf4119512777eea643fb72eca8010992454e` (PR #643, stacked on unmerged PR #642; do not merge).  
**Final exact-source GitHub Actions:** [#45230338091](https://github.com/775878805Osamaha/TradeLab/actions/runs/45230338091), **completed/success**. Actual runner log: **963 Flutter regression tests + 4 independent drawing-selection cases + 11 Yemen timezone/scale tests = 978 PASS, 0 FAIL**; Flutter Analyze **success**. All **25 Pine Stage 2 frontend cases** pass, including four newly added cases. No local Flutter/Dart executable or Android device verification; no APK.

### Source and test changes
- `flutter_app/lib/chart/pine_v6_semantic.dart`: resolve positional/named user-function arguments against declared parameters; detect unknown name, missing required argument, duplicate positional+named binding, incompatible primitive type and stronger-than-allowed `const/input/simple/series` qualifier. Track loop nesting so `break` and `continue` work only inside `for`/`while`, including nested `if`, without inheriting caller-loop context in a function definition. Fix overzealous "untyped na" detection: only a **literal na** needs explicit type; an as-yet-unresolved user-function return is not na.
- `flutter_app/test/pine_v6_frontend_test.dart`: four added tests for correctly reordered named args, five independent argument errors, legal nested loop controls and illegal top-level/local non-loop controls. Total Stage 2 tests now **25**.

### Test failure and repair
- [CI #45229881973](https://github.com/775878805Osamaha/TradeLab/actions/runs/45229881973): **FAILED**, runner reported **962 PASS / 1 FAIL**. The new valid-function-call test detected an incorrect `unknown_variable_type` diagnostic on a function return whose type is not yet inferred.
- Fix committed as `f135bf4119512777eea643fb72eca8010992454e`, preserving explicit `na` rejection without rejecting unresolved UDF returns. [Final CI #45230338091](https://github.com/775878805Osamaha/TradeLab/actions/runs/45230338091) passed all 978 checks (963+4+11).
- Earlier version annotation regex failure [CI #45225142962](https://github.com/775878805Osamaha/TradeLab/actions/runs/45225142962) **933 PASS / 26 FAIL** was previously fixed and documented. Never present failed/cancelled jobs as green.

### Current capability and scope limits
This is **only Pine v6 frontend semantic analysis**. The old Stage 1 numeric AST/evaluator is the sole executable engine. New UDF/loop/var/varip constructs remain parsed/validated but never evaluated by the runtime. The new type rules cover primitive declared parameters and qualifier ordering, not generic collections, overloads, inferred UDF return types or all built-in API signatures. Stage 3 remains **proposed**, not implemented. User V10 and unrelated projects are excluded; no modification to main, no APK or merge.

**PR status:** #642 and #643 remain draft/unmerged, and parallel alternative [#644](https://github.com/775878805Osamaha/TradeLab/pull/644) must NOT also be merged. Owner reviews #643 as the candidate stacked on #642. Once #642 is merged by owner, compare/rebase or retarget #643 safely, rerun CI, and merge only on owner action. Next technical task: Stage 3 runtime with real v6 var/varip/loops/UDF and Replay rollback/checkpoints plus bounded execution.

Official source for loop-only break/continue: https://www.tradingview.com/pine-script-docs/language/loops/ .


## Post-review quality follow-up — confirmed 2026-11-23

- **Final code + workflow commit:** `1d6f6bb97e2133cde701469ee309ee18e74bc70e` on PR #643. [Exact-head CI #45225811614](https://github.com/775878805Osamaha/TradeLab/actions/runs/45225811614) **completed/success**. GitHub log reports **959 primary Flutter tests + 4 drawing checks + 11 Yemen/timezone scale tests = 974 passed, 0 failed**. Flutter Analyze passed and all **21 Stage 2** tests, including 2 new version tests, passed. No locally run Flutter/Dart tests and no APK.

- **Added strict version gate without replacing existing execution:** `pine_v6_frontend.dart` rejects an explicitly annotated `//@version=5` (or any non-v6 annotation) with `version_mismatch` and source location rather than executing it under v6 assumptions. Existing unannotated numeric scripts remain executable **only as a documented backward-compatibility exception**. Official Pine semantics treat unannotated source as v1, so this exception is not full v6 parity. See [TradingView script structure](https://www.tradingview.com/pine-script-docs/language/script-structure/). Two regression tests added to `pine_v6_frontend_test.dart`.

- **Failure preserved:** [CI #45225142962](https://github.com/775878805Osamaha/TradeLab/actions/runs/45225142962) failed **933 passed / 26 failed** because the new version guard mistakenly used the inline regex flag `(?m)`, unsupported by Dart's RegExp implementation. Corrected to `RegExp(..., multiLine: true)` in commit `c45d112d5d0bf061be1e0da3749f67678c0fc2ad`; the subsequent exact-head CI above is green. This failure is **not** evidence of a newly broken runtime remaining in the final code.

- The dedicated no-APK workflow now uses push path filtering for Flutter/workflow changes, avoiding full-test reruns on documentation-only commits.

- **Parallel PR warning:** [#644](https://github.com/775878805Osamaha/TradeLab/pull/644) is an independent alternative frontend targeting the same Stage 1 branch. **Do not merge both #643 and #644**; they contain competing lexer/parser/AST stacks. #643 is recommended as the primary review candidate, with broader coverage (21 frontend tests and 974 green), while #644 remains draft/unmerged. Nothing was merged or deleted. The owner will make the merge decision.

**Status:** Stage 2 frontend source implemented and CI-verified. **PR #643 DRAFT / NOT MERGED**: https://github.com/775878805Osamaha/TradeLab/pull/643

**Dependency:** Stage 1 PR #642 is still open and unmerged at implementation time: https://github.com/775878805Osamaha/TradeLab/pull/642 . Therefore this Stage 2 branch is deliberately based on its feature branch and PR #643 targets feat/pine-stage1-instance-safe-runtime-20261123. Nothing was merged into main or development by the assistant. Rebase/retarget to the agreed Flutter integration branch only after the owner merges Stage 1.

**Scope:** TradeLab Flutter only. No development/use of excluded personal V10, no OMEX or OMX ERP changes, no Android APK/Release, no Kotlin migration, no new Pine runtime semantics in this stage.

## 1. Mutation testing was run first (proof of negative controls)

Two throwaway GitHub branches with NO PR and with NO changes to the real implementation branch:

1. test/pine-stage1-mutation-replay-20261123, commit b3152add7ea3df44e0eb4331455ccba90560e590. Deliberately changed the Replay prefix loop to read index == visibleCount. GitHub Actions [#45217673219](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217673219) **completed/failure as expected**, targeted test file **7 passed / 1 failed**, with observed reads [0,1,2,3] when indices must be less than 3. Failing assertion in pine_stage1_runtime_test.dart proves the test detects this mutation.
2. test/pine-stage1-mutation-state-20261123, commit 64a3698b3f20f8a980463b52ae93780e4c6e515b. Deliberately shared the persistentState map between two indicator instances. GitHub Actions [#45217676913](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217676913) **completed/failure as expected**, targeted test file **7 passed / 1 failed**; secondary copy unexpectedly held counter=4 and failed isolation assertion.

The mutations remained on isolated branches and were **never used in Stage 2 source, PR #642 or the Flutter development branch**. These two negative controls demonstrate coverage for those exact defects, not full mutation-test coverage of the engine.

## 2. Code actually written in Stage 2

| File | Delivered behavior |
|---|---|
| flutter_app/lib/chart/pine_v6_ast.dart | Source-located immutable AST for literals, identifier/member/calls, named arguments, unary/binary/ternary, history, tuples, variables and reassignment, if/else, switch, for/while, functions, parameters, controls; stable JSON snapshots; typed diagnostics and span |
| flutter_app/lib/chart/pine_v6_lexer.dart | Bounded tokens with indentation/dedent, multiline/triple strings, numbers/exponents, colors, comments, operators, parentheses and continuation; line/column |
| flutter_app/lib/chart/pine_v6_parser.dart | Pratt expression parser, typed declarations, := and compound assignment, var/varip, if/switch/for/while, function signatures/bodies, member namespaces, positional/named args; recovery at statement boundaries |
| flutter_app/lib/chart/pine_v6_semantic.dart | Nested scope and name resolution, primitive types int/float/bool/string/color, qualifier strength (const/input/simple/series), duplicate-name/type/condition/arity checks, global-only plot-family and indicator declarations, function global reassignment and recursion checks |
| flutter_app/lib/chart/pine_v6_frontend.dart | Separate parse/semantic eligibility from execution. Valid existing numeric scripts return executableSubset and continue on the original interpreter; analyzed valid but nonexecutable constructs return parsedButNotExecutable and semantic not_yet_supported; invalid source returns diagnostic instead of executing |
| flutter_app/lib/chart/chart_indicator_library.dart | Safe frontend gate for saved Pine scripts and user-facing Arabic line/column diagnostics; original numerical parser/AST/evaluator retained. Old supported scripts remain executable |
| flutter_app/test/pine_v6_frontend_test.dart | 19 new tests: lexer and wrapping, AST/flows/functions and snapshots, semantic recovery/scope/types, global plot rule, deadlines/source limits, unsupported safety, numerical differential fixtures for the full currently recognized set of TA/math operators |
| .github/workflows/verify-flutter-range.yml | Includes frontend tests in existing full Flutter regression suite |
| .github/workflows/pine-v6-stage2-no-apk.yml | Dedicated no-APK push CI for the stacked Stage 2 branch, using the same complete Flutter test/verification steps |
| docs/PINE_V6_LANGUAGE_SUPPORT_STAGE2_2026-11-23.md | Up-to-date parsed/executable/not-yet-supported language matrix and official specification references |
| docs/PINE_STAGE2_HANDOFF_2026-11-23.md | This report |

**No new runtime implementation:** Stage 1 numeric PineBarExecutor remains the executor; var/varip persistence, loops, dynamic user functions, realtime intrabar rollback, request.* and advanced visuals are AST/analysis only and must never produce an invented chart result.

## 3. Test proof, failures and corrections

**Final passing source-code CI:** [GitHub Actions #45222318255](https://github.com/775878805Osamaha/TradeLab/actions/runs/45222318255), source HEAD **f74d1d529bc490b2211fb7e14da7ee3acf9940c7**, **completed/success**.

Actual job log results:
- **957 passed** in main Flutter regression test invocation (includes **19 new Stage 2 tests** and **8 Stage 1 tests**, plus existing Pine, chart, Replay, Range, paper trading and results tests).
- **4 passed** in targeted drawing catalog tests.
- **11 passed** in chart timezone/scale test invocation with Yemen timezone.
- Total **972 passed, 0 failed** across these invocations. Flutter analyze (--no-fatal-infos) succeeded.

Previous real CI failure rounds preserved and corrected:
- [#45220150867](https://github.com/775878805Osamaha/TradeLab/actions/runs/45220150867) FAIL: Flutter analyzer identified an unused import, corrected.
- [#45220388995](https://github.com/775878805Osamaha/TradeLab/actions/runs/45220388995) FAIL: **950 passed / 6 failed**, including multiline block-boundary and color named-argument parser handling, corrected.
- [#45221079799](https://github.com/775878805Osamaha/TradeLab/actions/runs/45221079799) FAIL: **955 passed / 1 failed**; semantic analyzer treated valid plot.style_histogram enum as an undeclared name, corrected by builtin namespace recognition.
- Later intermediate runs cancelled by new commits were superseded, not marked as passed.

**Local environment:** Flutter/Dart toolchain is not installed locally. No local Flutter analyze/test claim. The proof is the GitHub CI job logs, not a device verification. No Android Profile/frame-time benchmark, live cTrader feed test, signed APK or screenshot goldens with missing checked-in baselines were run. CI skips unavailable optional goldens per the existing project workflow.

## 4. Reality-based acceptance / limitations

- Lexer/parser/AST/semantic: **implemented and CI-tested for the documented subset** including stage-2 requested constructs, not exhaustive grammar of all Pine v6.
- line/column category diagnostics and error recovery: **implemented and CI-tested**.
- no silent execution of unsupported scripts: **implemented and CI-tested**; valid syntax with unimplemented execution is explicitly labeled.
- differential parity: **tested in representative fixtures spanning all currently supported TA/math functions and operators**; not a proof of every possible valid script.
- full Pine v6 type resolution, overload signatures, advanced collection/UDT/type/method definitions and all builtin API signatures: **partial/not implemented**. See language matrix.
- analysis budgets are cooperative. They do **not** provide preemptive isolation or a guarantee that arbitrary parsing never blocks the Android UI; a later isolate/cancel pass remains needed.
- Stage 1 core instance runtime and Replay prefix safety remain unchanged. CI indicates regressions did not occur in tested cases; physical-device fidelity is not established.

## 5. Next task: Stage 3 (proposed, no code implemented here)

Build the executor for already-parsed constructs: var/varip state across historical bars/realtime tick rollback, scopes and qualifier-aware expression semantics, if/switch/for/while and user-defined function calls; register supported builtin functions explicitly; enforce step/memory/deadline budgets and recursion/loop bounds; implement Replay snapshot/rebuild tests and anti-lookahead guards before activating any new grammar in the chart. Add differential fixtures versus public Pine behavior, no fake values. User review and new PR required; do not merge unreviewed work.

**Handoff instruction:** Check current PR #643 head/CI and PR #642 merge status, read this report and the language matrix, then proceed only from confirmed repository state. Leave both PRs unmerged pending owner action.
