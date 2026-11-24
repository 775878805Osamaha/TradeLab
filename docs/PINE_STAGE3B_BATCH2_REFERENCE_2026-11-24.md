# Stage 3b batch 2 — reference expansion only

Batch 1 exact head a1cbf80d3101768c18913e7de66dc56f8436bf52: [dedicated CI](https://github.com/775878805Osamaha/TradeLab/actions/runs/45291910237), [PR CI](https://github.com/775878805Osamaha/TradeLab/actions/runs/45291919336), each 1053+4+11 = 1068 PASS / 0 FAIL. All 52 new tests passed; analyzer passed with 373 nonfatal infos. #647 stays open, unmerged. This stacked branch does not modify runtime, AST, parser, semantic analyzer, old parser or TA registry; no new functions, no APK.

## Long reference source
360 synthetic standard-candle OHLCV rows, integer price ticks, fixed LCG seed 20261124, trend/reversal/consolidation, occasional opening gaps, varying ranges and volume. Not real market data. Generator tools/pine/generate_stage3b_reference.cjs uses independent analytic weighted sums with compensated summation (not the Dart recurrence), explicit seed rules and no app imports. Round stored expected values to 9 decimals. CI checks byte-for-byte reproduction via node --check mode; generation is not done by the application. EMA seed first close; RMA and ATR seed first length values, RSI seed length close-to-close gains/losses; ATR first TR high-low. Dense only; missing-value policy remains internal batch-1 tests. Lengths 14 and 50; compare every row and explicitly bars 1,10,50,300,360 (one-based); also check first defined bar and seek 360->1->10->50->300->360 with continued stepping. EMA/RSI legacy routes independently checked. No captured TradingView output. All 16 support rows: internally tested with independent formula; long-reference coverage only four; no TradingView parity claim. Batch 2 CI required.

## Proposal only: future MACD/BB tuple declarations
Current canonical AST has PineTupleExpression and PineVariableStatement, parser supports tuple expressions but not a tuple declaration binding; semantic model exposes tupleType without per-element binding types. Language runtime currently excludes signature.tupleResult from admitted TA calls and uses one scalar binding per declaration. Library already returns lists for ta.macd/ta.bb. Do not change any of these in batch 2.

Proposed separate work only after explicit owner approval:
1. Add distinct PineTupleDeclarationStatement with ordered target names/spans and one RHS. Parser disambiguates [a,b,c] = expr from bracket history and tuple expressions; reject :=, arity mismatch, duplicate/redeclared targets except discard _, invalid scope. Preserve existing AST snapshots for scalar code.
2. Semantic analyzer resolves tuple signature component types/qualifiers, checks exact arity before introducing bindings, validates local scope and discard names, rejects tuple used in scalar contexts; preserve scalar and legacy fallback diagnostics. Only MACD/BB initially, not arbitrary function tuples.
3. Advanced runtime evaluates RHS once per written call and closed bar, validates tuple size and finite/na component types, atomically declares individual bindings and tracks series/history independently. No duplicate EMA advancement, no aliasing mutable output, no new global state. Retain call-site identity and Replay prefix rebuild/rollback guarantees. Plot individual numeric bindings; preserve existing plot limits. Legacy engine and duplicate frontend untouched.
4. Regression gate: AST parsing and diagnostics, scope/redeclaration/discard cases, arity and invalid syntax, per-call state/isolation, na/warmup, numeric values against independent references, history index and no-future Replay with rewind/continue, saved script chart integration, existing entire CI. Risks: ambiguity with [] history, semantic qualifier errors, partial binding on failure, double computation, shifted history, tuple leakage into scalar operators and legacy routing. Do not claim TradingView parity without real capture. No implementation approved or attempted here.

## Actual TradingView CSV follow-up (same batch 2, not batch 3)
Owner supplied original CSV, SHA-256 64b557c209f44c387a127bdf213703d4858fa3d62305711a12630713422221b3. Original Git blob verified before referencing in tree. Mandatory direct CSV tests use zero-based indices 300..997 inclusive; exclude final row at owner instruction (no closure flag in CSV). Prefix 0..299 diagnostic only. Four library and advanced runtime comparisons, legacy EMA/RSI comparisons, guarded Replay 700->400->700, integrity and matrix gate; structured TV_CAPTURE_STATS log for per-route maxima and first/last warmup values. Strict absolute <=1e-6. No code changes to runtime, no merge, no new batch. Exact head CI pending. Prior batch 2 head 000b9bc9a8c1915b0056f227bd2ba9d9463e7e05 CI 45292700540: 1089 PASS / 0 FAIL / 1 SKIP (optional external JSON). Independent arithmetic preliminary check of original CSV across 698 reference rows passes for all four; not evidence of application execution. Matrix classification conditional until CI passes.

## Final actual Dart evidence, 2026-11-24
Exact tested head `0ce365013639f70d2fc588f562e6dbb9dd2ebb9d`, [CI 45407514078](https://github.com/775878805Osamaha/TradeLab/actions/runs/45407514078), job 138492143019: 1084+4+11=1099 PASS / 0 FAIL / 1 SKIP (additional optional JSON only). All ten mandatory CSV cases passed, including four Replay cases. Source SHA-256 and independent 360-bar reproduction passed. Analyzer passed with 373 nonfatal infos. No numerical failure. Machine-readable parsed CI measurements: `docs/evidence/PINE_STAGE3B_TVC_GOLD_DART_CI_45407514078.json`. Library and advanced Pine are exactly equal; legacy EMA/RSI within same limit. Relative error = abs(actual-reference)/abs(reference), not percent; maximum indices are zero-based and may differ. The matrix records scoped verification, not blanket TradingView equivalence. This metadata/test-assertion follow-up must pass fresh CI before merge; the measured engine source is unchanged.

| Function | Route | Max abs | Index | Max relative | Index |
|---|---|---:|---:|---:|---:|
| ta.ema | library | 5.093170329928398e-11 | 458 | 1.3511059087501156e-14 | 980 |
| ta.ema | pine | 5.093170329928398e-11 | 458 | 1.3511059087501156e-14 | 980 |
| ta.ema | legacy | 5.093170329928398e-11 | 395 | 1.3672296876791657e-14 | 970 |
| ta.rsi | library | 3.2247626791104267e-9 | 300 | 5.418948883780874e-11 | 300 |
| ta.rsi | pine | 3.2247626791104267e-9 | 300 | 5.418948883780874e-11 | 300 |
| ta.rsi | legacy | 3.2247626791104267e-9 | 300 | 5.418948883780874e-11 | 300 |
| ta.atr | library | 4.646079077019749e-10 | 300 | 3.770779633847076e-11 | 300 |
| ta.atr | pine | 4.646079077019749e-10 | 300 | 3.770779633847076e-11 | 300 |
| ta.rma | library | 6.13727024756372e-9 | 300 | 1.4702244473361661e-12 | 300 |
| ta.rma | pine | 6.13727024756372e-9 | 300 | 1.4702244473361661e-12 | 300 |

### Known warm-up limitation and Replay
When available history starts later than TradingView's calculation history, EMA/RMA/ATR/RSI can differ or be na during early bars. Indices 0..299 of this capture are diagnostic only; approximately 300 preceding available bars is a tested cutoff for this capture, not a universal convergence guarantee. Replay near the beginning of available history may show different values; never use future candles or seed from reference outputs.

| Function | First valid index | na count | over 1e-6 (numeric) | max abs | index | max relative | index |
|---|---:|---:|---:|---:|---:|---:|---:|
| ta.ema | 0 | 0 | 106 | 3.575847048899959 | 0 | 0.0008327221575192317 | 0 |
| ta.rsi | 14 | 14 | 207 | 3.6029596352123505 | 14 | 0.078410589043161 | 15 |
| ta.atr | 13 | 13 | 182 | 0.7178058839427983 | 13 | 0.04117196341026372 | 13 |
| ta.rma | 13 | 13 | 219 | 10.640979388885171 | 13 | 0.00248510682350898 | 13 |

TradingView has values at row 0 because its calculation history predates the supplied CSV; TradeLab starts from the first supplied OHLC bar. No initial state seeding or changes to formulas. The early-window counts above exclude na from numeric over-tolerance counts. All four Replay tests at counts 700 -> 400 -> 700 passed, identical to direct execution, no hidden future reads. Scope excludes earlier indices, other symbols/timeframes/lengths, intrabar and other functions.

### Owner merge order
At verification: integration `bf993d298fc4e31cecf47bbb8bb3a31b29fd5b1d`; #647 exact head `a1cbf80d3101768c18913e7de66dc56f8436bf52`, 2 ahead/0 behind, mergeable, CI 1068/0. #648 stacked on #647, 4 ahead/0 behind at tested head, mergeable. Shared paths: .github/workflows/verify-flutter-range.yml and flutter_app/test/fixtures/pine_stage3b_support.json. Normal merge commit of #647 preserves ancestry, so no textual conflict expected if base stays unchanged; after owner merge verify integration and CI, retarget #648 to integration, check its exact delta and rerun CI before owner merge. If squash/rebase or parallel edits occur, compare actual trees and resolve manually before merging. No assistant merge, no batch 3.
