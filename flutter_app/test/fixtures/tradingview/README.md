# Fixed genuine TradingView CSV capture

- Original unmodified user-provided Pine Logs export: `4_5778588908598075071.csv`, from TradeLab Reference Capture / TradeLab Reference Logs, TradingView TVC:GOLD, standard candles, 60-minute (1h), length 14.
- Export date: 2026-11-24 (exact export time and session settings not recorded). 999 rows, UTC 2026-09-24T02:00:00Z through 2026-11-24T12:00:00Z. SHA-256: `64b557c209f44c387a127bdf213703d4858fa3d62305711a12630713422221b3`; original 156165 bytes, LF, Git blob `51835ba5300c07e5755ca8fe7b6e8ad3c1bb3e20`.
- User identifies final row (index 998) as indicative/unclosed. CSV itself has no confirmation flag: preserve original row but exclude it from all computation/comparison. No resampling, interpolation or fill; preserve session gaps.
- Indices are zero-based. Rows 0..299 are input warmup and diagnostic-only, because TradingView started calculation before the export; no initial state is seeded from reference indicators. Reference window indices 300..997 inclusive (698 rows). Absolute tolerance <= 1e-6, no relative tolerance relaxation; relative error is logged separately. Source is original Message OHLCV; volume retained/validated separately because TradeCandle stores OHLC only and these four functions do not use volume.
- Mandatory CSV test compares library, advanced Pine runtime, legacy EMA/RSI and guarded Replay 700->400->700 (counts). A mismatch stops the parity gate; no engine adjustment or tolerance change in this PR. Scope limited to TVC:GOLD 1h, length 14, selected window. Matrix stays pending until actual exact-head CI verified.

## Optional additional JSON capture template

# Actual TradingView capture (optional; no values supplied)
Copy pine_stage3b_actual.template.json to pine_stage3b_actual.json and replace null metadata plus empty rows with a real exported dataset, not the synthetic fixture. Keep the untouched template. The optional Flutter test is explicitly skipped with a reason when the actual file is absent; a present malformed/empty file fails.

- Export standard candles, same exact exchange-qualified ticker, timeframe, session and history. Set UTC ISO-8601 bar times (with Z), export time, and history start (first supplied row).
- Compute EMA(close,14), RSI(close,14), ATR(14), RMA(close,14) on TradingView. Export OHLCV and all four values for the same closed bars. Use JSON null for unavailable values (never zero or a string). No resampling, no forward fill, no fake rows. Preserve at least 300 ordered bars; at least 50 bars must be compared.
- Document any unseen TradingView history/seed mismatch in historyAlignmentNote. Ideally start at the same first calculation bar; otherwise retain substantial preceding history and set compareFromBarOneBased to a justified warmup boundary. This is not proof of first-bar parity if the platform has hidden prehistory.
- Set tolerance no greater than 1e-6 absolute and 1e-8 relative; preserve export precision. A failure must be investigated, not hidden by changing tolerance. This test compares only the four scalar functions, length 14, selected capture, closed bars, not all TradingView behavior.
- Pine snippet for the user's actual export:
```pine
//@version=6
indicator("TradeLab reference capture")
plot(ta.ema(close,14), "ema")
plot(ta.rsi(close,14), "rsi")
plot(ta.atr(14), "atr")
plot(ta.rma(close,14), "rma")
```

## Verified scoped result
CI 45407514078, exact head `0ce365013639f70d2fc588f562e6dbb9dd2ebb9d`: 1099 passed, 0 failed, 1 skipped (optional additional JSON only); all 10 CSV tests passed. See `docs/evidence/PINE_STAGE3B_TVC_GOLD_DART_CI_45407514078.json`. When available history starts later than TradingView's calculation history, EMA/RMA/ATR/RSI can differ or be na during early bars. Indices 0..299 of this capture are diagnostic only; approximately 300 preceding available bars is a tested cutoff for this capture, not a universal convergence guarantee. Replay near the beginning of available history may show different values; never use future candles or seed from reference outputs.

## Second fixed genuine capture — TradeLab Reference Logs V2
- Original user attachment: pine-logs-TradeLab Reference Logs V2.csv, TVC:GOLD, 1h, first chart bar per owner. SHA-256 6a052a535dc4bf77d3687a10446e9572bdf523a3bc80e2fe728a2c290899da7f, Git blob dd6012ecd50c1d3ecc0eb39eb38c443194f28b4b, 1548728 bytes, 5336 LF-terminated lines including header. Original bytes verified. Outer CSV Date,Message; each quoted Message has 26 fields symbol,time_ms,O,H,L,C,V,macdL,macdS,macdH,diP,diM,adx,stV,stD,haO,haH,haL,haC,ph,pl,barssince,sma,stdev,highest,lowest. 5335 ascending rows from 2026-01-01T23:00Z to 2026-11-25T13:00Z; last row excluded from ALL computations, preserved on disk. No artificial fill of session gaps.
- Settings: MACD(12,26,9), DMI(14,14), Supertrend(3,10), pivot(5,5), barssince(close>open), SMA(volume,20), biased stdev(close,20), highest(high,20), lowest(low,20). NaN means numeric na. Absolute tolerance 1e-6, exact missing mask. Actual capture first valid indices MACD L25, S/H33; DI+/-14, ADX27, ST value 0 (special), 1..8 na, 9 first ATR-backed, direction 1 during warm-up; HA0; PH19, PL24; barssince0; last four rolling values19. Confirmed via local parsing; not yet a Dart result.
- HA seed (O+C)/2 and OHLC mean. Exclude indices 5273..5290 inclusive only in HA reference comparison (18 rows); retain inputs and recursive state. Source discrepancy reported by owner (one close discrepancy 0.015); no reference values injected. 5316 eligible HA comparisons. Pivot low accepts left equal/right rejects, reported indices 3982,5067,5068. Pivot high tie policy unverified. No hidden warmup or tolerance relaxation. MACD SMA-seed candidate tested independently; standalone EMA not directly exported. Existing executable EMA remains unchanged until separately resolved.
- Mandatory Dart test tradingview_reference_v2_test.dart compares all 19 output columns using calculation candidates and existing scalar TA library, and replays 3000→1000→3000 with OHLC and volume poison guard. It is a calculation-level test, not proof of generic Pine runtime wiring or trading simulator. JSON metrics in build/pine_audit/tradingview_v2_parity.json and TV_V2_COLUMN log. Pending exact-head CI, no parity claims yet.

Actual Dart CI 45707533239 passed 1191/0/1; all 19 columns zero mismatches at 1e-6 and exact na mask. Evidence: docs/evidence/PINE_TRADINGVIEW_V2_DART_CI_45707533239.json. This is scoped calculation parity, not interpreter activation. New transfer test reports max-error index and uses source metadata model; new-head CI pending.
