# TradeLab — Pine v6 language support matrix, Stage 2

Date: 2026-11-23. Scope: general TradeLab Flutter indicator syntax. Stage 2 is **frontend only**. No new Pine control-flow execution is authorized. No APK, no main branch changes, no excluded custom script.

Source: flutter_app/lib/chart/pine_v6_ast.dart, pine_v6_lexer.dart, pine_v6_parser.dart, pine_v6_semantic.dart, pine_v6_frontend.dart. The existing Pine numeric interpreter in pine_subset_program.dart remains intact.

Definitions: **PARSED** means tokenization, AST creation and the implemented semantic checks. **EXECUTABLE** means the old bounded Pine subset executes it using verified source candles. **NOT YET EXECUTABLE** means the frontend refuses to run it with not_yet_supported. **REJECTED** means a detectable invalid construct or still-unrecognized syntax. This matrix is not a claim of complete Pine v6 grammar validation.

| Capability | Frontend | Runtime | Notes |
|---|---|---|---|
| Version annotation, line comments | Parsed/ignored safely | Existing numeric scripts execute | No automatic version conversion |
| Four-space indentation, dedents | PARSED | No new runtime | Local scopes |
| Parenthesized and trailing-operator line wrapping | PARSED | Existing subset only | Unparenthesized continuation cannot resemble a block |
| Numbers, ordinary/triple strings, bool, na | PARSED with primitive types | Numeric values only | Other types remain analysis only |
| Hex color literals and color namespace | PARSED | Fixed old plot palette only | No arbitrary color execution |
| int, float, bool, string, color | PARSED and type checked | Numeric int/float subset only | Collection/reference types excluded |
| const, input, simple, series qualifiers | PARSED and basic qualifier-lattice checks | Numeric input.int/float default only | Not full overload semantics |
| indicator declaration and overlay | PARSED | EXECUTABLE in existing subset | Existing chart output unchanged |
| Numeric assignment, arithmetic, historical x[n] | PARSED | EXECUTABLE in existing subset | Stage 1 na and history |
| Built-in ta.sma/ema/rsi/roc/highest/lowest/change | PARSED | EXECUTABLE in existing subset | Source-verified prefix |
| math.abs/min/max and nz | PARSED | EXECUTABLE in existing subset | Other math namespace APIs parsed but not executed |
| Global plot with supported styles/title/color/width | PARSED with global-scope checks | EXECUTABLE, bounded to 8 plots | Plot-style enum treated as builtin property |
| Compound assignment and := | PARSED with name/type checks | NOT YET EXECUTABLE | Stage 3 |
| var and varip | PARSED with type/scope checks | NOT YET EXECUTABLE | Stage 3 persistence/rollback |
| if/else and ternary | PARSED with branch/condition checks | NOT YET EXECUTABLE | Stage 3 |
| switch with condition/value arms | PARSED | NOT YET EXECUTABLE | Stage 3 |
| for/to/by and while | PARSED with scope and bound/condition checks | NOT YET EXECUTABLE | Stage 3, step budgets required |
| User-defined functions, typed/default parameters | PARSED with arity/type checks | NOT YET EXECUTABLE | Stage 3 |
| Named arguments and member namespaces | PARSED | Only explicitly supported functions execute | Includes ta, math, array, color, str, input, timeframe |
| request.* namespace | PARSED and minimally typed | NOT YET EXECUTABLE | No cross-timeframe future-lookahead |
| Global plotshape, plotchar, plotarrow, plotbar, plotcandle, hline, fill, bgcolor, barcolor | PARSED | NOT YET EXECUTABLE | Visuals engine later |
| Local-scope plot-family calls | REJECTED | REJECTED | Official Pine global-only visualization rule |
| Unknown identifier, duplicate declaration in one scope | REJECTED with line/column | REJECTED | Multiple diagnostics |
| Incompatible primitive types, bool initialized with na | REJECTED | REJECTED | Pine v6 bool cannot be na |
| Function nesting, detected recursion or global reassignment | REJECTED when detected | REJECTED | Partial semantic coverage |
| Advanced collection generics, UDT, enum, matrix/map, strategy orders | NOT FULLY SUPPORTED | NOT EXECUTABLE | Not promised in Stage 2 |

## Safety and diagnostic contract

- PineDiagnostic stores stage (lexer, parser, semantic or compatibility), code, message, severity and **one-based line and column**; parser synchronization and semantic processing report multiple independent errors, with up to 48 diagnostics per stage.
- Lexer source budget: 60,000 UTF-16 code units, 12,000 tokens, 64 indent steps and cooperative 3-second limit. Parser: 16,000 AST work units, 3-second limit. Semantic: bounded symbols/work and 3-second limit.
- These deadlines are cooperative, **not** preemptive isolates. Stage 8 must measure and move heavy work off the chart UI thread before claiming nonblocking Android execution.
- Legacy numeric compiler retains 15,000-character cap and Stage 1 execution budgets. A script may be well formed but intentionally **not executable**. It is never silently converted to a fake moving average.
- PineV6Frontend.prepare returns one of executableSubset, parsedButNotExecutable, invalid. The second status includes a semantic severity=unsupported diagnostic with code not_yet_supported.
- ChartSavedIndicatorScript uses the new analysis gate for arbitrary saved source, while already-executable numerical scripts retain the existing runtime. Unsupported scripts stay savable; the UI message includes Arabic line, column, code and reason.

## Official behavior references

- https://www.tradingview.com/pine-script-docs/language/script-structure/
- https://www.tradingview.com/pine-script-docs/language/type-system/
- https://www.tradingview.com/pine-script-docs/language/variable-declarations/
- https://www.tradingview.com/pine-script-docs/language/user-defined-functions/
- https://www.tradingview.com/pine-script-docs/faq/techniques/
- https://www.tradingview.com/pine-script-docs/visuals/plots/

**Limit:** This is the implemented frontend subset, not a universal Pine v6 compiler. Full overload/type-system fidelity, tuple and UDT forms, all builtins, realtime rollback/commit, actual Android hardware parity and exact TradingView results remain unverified. Stage 3 is the next execution phase.
