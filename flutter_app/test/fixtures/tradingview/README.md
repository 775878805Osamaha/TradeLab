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
