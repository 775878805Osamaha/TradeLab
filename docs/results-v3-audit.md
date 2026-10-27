# Results V3 audit and target

Base: c6368cd62bbe5d6efd2b243127cb1585c0cfc72a (PR389), contains the funded Replay account. Main is 2bf646f; pending PR387/388 are ancestors. No main merge.

Existing path: ExecutionEngine.closePosition -> ReplayViewModel closedTrades and equitySamples -> TrainingSessionStore AtomicFile; reportSink -> TradingRepository.replayReport -> ResultsViewModel. Room v2 holds legacy accounts/trades but the funded training journal was not its source. Navigation is MainActivity (four destinations).

New path: execution snapshot -> Room transaction (checkpoint, decimal balance/funding, unique ordinal closed-execution ledger) -> Room @Transaction Flow -> training analytics on Dispatchers.Default -> Results V3. Import the existing AtomicFile on first Room read. Do not serialize any added fields into the old Java classes; preserve checkpoints. New Room tables do not create a second wallet or touch legacy accounts/trades.

Reference: docs/references/results-v3.png, 691x1536 pixels. Target density 276 dpi => 400.58dp x890.43dp. OS chrome is excluded.

Measured region bounds in source pixels (approximate boundary antialiasing): header y48..130; tabs y130..189; filters y207..252; hero x14..679 y268..688; metric rows y700..809,819..930,939..1051; latest trades y1064..1368; existing bottom navigation y1387..1489. Main margins 14..19px, gaps 10..13px. Palette starts from requested #020D18/#061725/#193447/#2962FF/#00D5B0/#FF4D60, secondary #8E9DB1. The provided identity mark alone is extracted as an asset; UI, metrics and charts are native Compose.

Money: initial funding is the opening capital, also disclosed as total deposits; it is never added twice. No later deposits or withdrawals are exposed in this single account. Net P/L is journal.netProfitLoss, already after allocated commission/swap and execution bid/ask spread. Analytics sums use BigDecimal; engine's existing Double execution behavior is preserved. Equity is actual observed floating-inclusive equity. Partial exits count as separate closed executions, each once.

Calendar filters use Room recordedAt (training activity). Market open/close timestamps remain unchanged in trade details. Start balance carries all earlier realized results; filtered P/L never includes those trades. Drawdown uses observed equity within range, starting from the prior equity observation. Sharpe uses sample standard deviation of daily net balance returns, unannualized, minimum two days. Breakeven stays in denominator, resets win/loss streaks, and contributes zero to expectancy. Profit factor with positive gains/no losses is unbounded (∞), no outcomes is —. R requires an actual nonzero stop-risk basis.

Reference numbers/curve are examples; no reference prices, profits or trades enter production. Native screenshot coverage executes orders on provider-backed GBPUSD Replay and displays its persisted outcomes, so sign/shape/time-span differences are expected.
