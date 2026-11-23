# TradeLab — Pine v6 Stage 2 frontend handoff (2026-11-23)

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
