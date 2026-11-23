# TradeLab — Pine v6 Stage 2 Frontend Support Matrix (2026-11-23)

**Branch:** feat/pine-stage2-frontend-v6-20261123  
**PR:** https://github.com/775878805Osamaha/TradeLab/pull/644 (draft; stacked on unmerged Phase 1 PR #642)  
**Scope:** Lexer / Parser / AST / Semantic ONLY, plus safe legacy executable dispatch. No execution of Phase 3 language constructs, no APK, no main.

The stages differ: "Parsed" means the structure is represented in a source-spanned AST. "Semantically checked" means the specified primitive/scope rules are checked, not complete formal v6 validation. "Executed" means the old bounded PineSubsetProgram runtime accepts it and keeps its numerical output; AST alone never implies executable behavior.

| Language feature | Tokenized / parsed | Semantic checks | Runtime execution |
|---|---|---|---|
| v6 version annotation, // comments and inline comments | Yes | Version check (v6) | Existing subset when valid |
| Four-space/tab local indentation and dedents | Yes | Scope trees | No control-flow execution |
| Wrapped calls/parenthesized expressions, operator continuation | Yes for covered forms | Expression trees | Existing subset only; multi-line old compiler may reject |
| Numeric constants and exponent notation | Yes | int / float | Existing supported decimal syntax only |
| Single, double and triple-quoted string literals | Yes | string | Only legacy string use in declaration/plot options |
| Hex colors (#RRGGBB / #RRGGBBAA), color constants | Yes | color | Legacy fixed color constants only |
| Basic assignment, :=, +=/-=/*=/= | Yes | symbol lookup, types | First assignment subset only; := and compound operators not executed |
| var / varip declarations | Yes, persistence AST enum | Type/qualifier of declaration | NOT EXECUTED |
| bool/int/float/string/color primitive type names | Yes | Widening int→float; incompatible types rejected | Numeric-only subset |
| const/input/simple/series qualifiers | Yes | Qualifier strength across expressions | NOT a complete v6 runtime type system |
| if / else-if / else blocks | Yes | Conditional value type and nested scopes | NOT EXECUTED |
| switch branches (including default), statement form | Yes | Case type compatibility and scopes | NOT EXECUTED |
| for ... to ... by ... / while | Yes | Numeric loop bounds and scopes / condition types | NOT EXECUTED |
| User-function declarations and parameter defaults | Yes | Parameter scopes, duplicate names, global definition, direct recursion | NOT EXECUTED |
| History indexing expression x[n] | Yes | Integer/nonnegative index | Legacy named-source constant history only |
| Calls with named arguments | Yes | Argument expressions/scoped identifiers | Legacy supported signatures only |
| Qualified namespace names, ta.*, math.*, input.*, str.*, color.*, request.*, timeframe.*, array.* | Yes | Broad primitive inference only; overloads not exhaustively resolved | Limited existing ta/math/input numeric functions only |
| Unary/binary logical/math/comparison, ternary ?: | Yes | Primitive type checks, qualifier propagation | + - * / only in legacy subset; no generic comparisons |
| plot / plotshape / hline / fill / other plot-related calls in local scope | Yes | Rejected as global_only | Legacy plot only in global scope |
| Unknown identifiers / redefinition / type mismatch | Yes | Structured diagnostics with line/column | Refused if invalid |
| Multiple recoverable parser/semantic errors | Yes for statement-separated invalid cases | Collects multiple diagnostics | Not executed |
| Whole-script untrusted size/time/token/AST-visit budgets | Yes, cooperative | Bounded checks | Existing Stage 1 step/memory/time limits for executable subset |
| Full Pine v6 constructs: tuples, arrays as typed values, maps, methods, custom UDT, library import, advanced generic overloads, realtime persistence | **NOT COMPLETE** | NOT COMPLETE | NOT EXECUTED |

## Safety and compatibility boundary

- Existing PineSubsetProgram remains the **only** runtime for scripts already supported. Stage 2 does not rewrite its AST evaluator. ChartSavedIndicatorScript exposes frontendAnalysis and a line/column "not executable yet" compileError for advanced source.
- Scripts that parse correctly but depend on var/varip, loops, functions, conditional blocks or other unsupported runtime features MUST be saved but cannot be activated as if they executed.
- The frontend cannot guarantee wall-clock preemption on the UI isolate. It has cooperative source length/token/time/visit budgets, and Stage 8 still requires cancellation and background execution.
- User-defined personal V10 strategy never used as a fixture, test or foundation.
- The original Kotlin app, Flutter Replay trades/results, Range history, broker data and existing chart visuals are not migrated or changed in Stage 2.

## Verified official Pine behavior references

- Script structure, indentation and multiline wrapping: https://www.tradingview.com/pine-script-docs/language/script-structure/
- Primitive types and qualifier hierarchy, restrictions on assignment: https://www.tradingview.com/pine-script-docs/language/type-system/
- plot/plotshape/barcolor/bgcolor and related output calls are global-only: https://www.tradingview.com/pine-script-docs/language/conditional-structures/
- User-defined functions have global definitions and cannot directly recurse: https://www.tradingview.com/pine-script-docs/language/user-defined-functions/

## CI status and next step

Before Stage 2, two deliberate mutants on a **separate branch without a PR** proved the existing tests detect the relevant bugs:
- Future Replay read [Actions #45217685758](https://github.com/775878805Osamaha/TradeLab/actions/runs/45217685758): **937 PASS, 1 expected FAIL**. Accessed index 3 after cutoff 3.
- Shared indicator persistentState [Actions #45218410206](https://github.com/775878805Osamaha/TradeLab/actions/runs/45218410206): **937 PASS, 1 expected FAIL**, second instance saw first's counter value.
- The temporary mutation branch was reset to the clean Stage 1 SHA ef917ad2c3dd3dc3e036e17b9dc1ead2d59631ee; neither mutation is included in the Stage 2 PR.

Stage 2 CI evidence is documented in docs/PINE_STAGE2_HANDOFF_2026-11-23.md. Do not merge until exact-head CI is green and the user reviews the PR. Next Stage 3: implement control-flow/stateful runtime semantics for AST constructs, with history, var/varip rollback and Replay safety.
