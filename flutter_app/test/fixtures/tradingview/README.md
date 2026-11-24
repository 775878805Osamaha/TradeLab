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
