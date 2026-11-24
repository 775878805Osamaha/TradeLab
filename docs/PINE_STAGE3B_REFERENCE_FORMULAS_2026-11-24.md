# Stage 3b batch 1 independent reference formulas

Source group manual-ohlcv-v1: synthetic six OHLCV rows in test/fixtures/pine_stage3b_ohlcv.json; no broker quotes, no TradingView output. Volume is recorded, not used (TradeCandle has no volume). Equations below were evaluated independently of application code; fixed numbers are checked into JSON, never produced by the Dart runtime during tests.

Close: 10,12,11,14,13,15. Length 2 unless specified. Cross threshold 13.5. Reference groups:
- SMA: arithmetic mean of last two, e.g. (10+12)/2=11.
- EMA: seed first close, alpha 2/3, E=(2*x+Eprev)/3. Sequence 10,34/3,100/9,352/27,1054/81,3484/243.
- RMA: seed (10+12)/2=11 then (previous+x)/2. WMA: (old+2*new)/3.
- RSI: differences 2,-1,3,-1,2; seed gain=1 loss=1/2; next gains/losses (2,1/4),(1,5/8),(3/2,5/16); RSI=100*g/(g+l).
- True range: max(H-L,abs(H-prevC),abs(L-prevC)); first true uses H-L; values 2,3,2,4,2,3. ATR RMA of TR length 2.
- Highest/lowest: maximum/minimum of two consecutive dense closes; first sample marked na (existing application warmup policy).
- Change/ROC: x[t]-x[t-2], 100*(x[t]-x[t-2])/x[t-2]. No output before two preceding bars.
- Population stdev: sqrt(sum((x-mean)^2)/2); with two values equals abs(new-old)/2. BB = [mean,mean+2*sd,mean-2*sd].
- MACD: EMA2 minus EMA3 (EMA3 sequence 10,11,11,12.5,12.75,13.875); signal EMA2 of line, starting 0; histogram=line-signal. Rational values evaluated independently and stored.
- Crossover/crossunder: previous <=/>= threshold and current >/< threshold; first false; crossing up at bars 3 and 5, down at 4 (0-based).

Documentation for definitions/signatures (not captured output): https://www.tradingview.com/pine-script-reference/v6/ ; tuple declaration https://www.tradingview.com/pine-script-docs/language/variable-declarations/ ; MACD https://www.tradingview.com/pine-script-docs/primer/first-indicator/ ; execution model https://www.tradingview.com/pine-script-docs/language/execution-model/ .

Scope: dense numeric formula comparison, not TradingView equivalence. Missing data, conditional calls and warmup are internal policy checks unless separately evidenced. Legacy extrema use full non-null windows; this may differ from TradingView. Fixed lengths 1..500, no dynamic series lengths, no one-argument highest/lowest, bool change overload, ta.tr variable form, tuple declaration/destructuring, realtime rollback, or volume-dependent TA. MACD/BB library-only; no script execution claim. All 16 receive dense-reference, na/warmup and prefix tests; tuple Replay is library prefix only. No external TradingView numbers available. No alternate parser or its tests modified/deleted. No APK.
