# TradeLab (منصة تداول واختبار الاستراتيجيات)

TradeLab is a professional, high-performance virtual trading, paper trading, historical replay, backtesting, and strategy analysis Android platform built with Kotlin, Jetpack Compose, and Material 3.

> **CRITICAL DISCLAIMER**:
> This application **NEVER** connects to live brokerage trading accounts and **NEVER** executes real money trading orders. All capital, balances, margins, and trades within the application are **100% VIRTUAL** for education, training, and research. However, all quotes, spreads, and market candlesticks are sourced from authentic market data.

---

## Key Features

1. **Native Dark Financial UI**:
   - Modern trading theme (`#121212` background, `#1E1E1E` cards, `#22C55E` profit green, `#EF4444` loss red, `#7C3AED` accent).
   - Full native **Arabic (RTL)** with comprehensive financial terminology and English LTR support.

2. **Professional Candlestick Chart (Android Canvas)**:
   - Real-time Candlesticks, OHLC, Volume bars, Current Price, Bid/Ask spread lines.
   - Smooth gesture navigation: multi-touch pinch zoom, horizontal pan, touch crosshairs with price/time chips.
   - Live visual overlays: Open Position entries (dotted), Stop Loss (red dashed), Take Profit (green dashed).
   - Technical Indicators: SMA, EMA (20/50), RSI, MACD, Bollinger Bands, ATR, VWAP.
   - Drawing Tools: Horizontal support/resistance lines, Trendlines, Clear.

3. **Three Isolated Trading Modes (Sharing the Same Core Engine)**:
   - **Live Paper Trading**: Manual virtual trading against real market ticks.
   - **Historical Replay**: Bar-by-bar progression with strict lookahead-bias protection. Speed controls from 0.5x to 100x, step forward/backward, and manual trading during replay.
   - **Algorithmic Backtesting**: Bar-by-bar simulation running strategies on historical candles without future leaks.

4. **Rigorous Execution & Risk Engine**:
   - Correct Bid/Ask execution: BUY fills at Ask, SELL fills at Bid, closing BUY at Bid, closing SELL at Ask.
   - Realistic Spread, Slippage, Commission ($5/lot), and Swap simulation.
   - Dynamic Margin validation preventing orders on insufficient virtual margin.
   - Advanced position actions: Modify SL/TP, Break-Even, Trailing Stop, Full and Partial Close.

5. **24+ Statistical Performance Metrics & Results Dashboard**:
   - Net Profit, Return %, Profit Factor, Win Rate, Total Trades, Expectancy, Max Drawdown ($ and %), Average Win/Loss, Sharpe Ratio, Sortino Ratio, Recovery Factor, R-Multiples.
   - Interactive Canvas **Equity Curve Chart** tracking Balance, Floating Equity, and Drawdown.

6. **Prop Firm / FTMO-Style Discipline Evaluator**:
   - Live tracking of Daily Loss Limit, Max Loss Limit, Profit Target progress, and Trading Days.
   - Algorithmic Discipline Score (0-100) reflecting strict adherence to risk management rules.

7. **Trade Journal & Trading Calendar**:
   - Searchable, categorized closed trade journal (ALL, WIN, LOSS, S/L, T/P).
   - Daily P/L summary calendar with color-coded positive (green) and negative (red) trading days and trade drill-down.

8. **Extensible Strategy Engine**:
   - Clean `Strategy` interface and `StrategyContext`.
   - Built-in strategies: EMA Crossover, RSI Mean Reversion, with architecture ready for FVG + HTF Bias and custom user algorithms.

---

## Clean Architecture

```
TradeLab/
├── core/
│   ├── model/          # MarketData, Order, Position, Account, Risk, Trade, Statistics
│   ├── market/         # MarketDataProvider abstraction, DefaultSymbols, Real quotes
│   ├── execution/      # ExecutionEngine (Bid/Ask, Slippage, Commission, SL/TP triggers)
│   ├── risk/           # RiskEngine (Margin calculations, Lot sizing, Risk % analysis)
│   ├── replay/         # HistoricalReplayEngine (Lookahead-bias-free progressive reveal)
│   ├── strategy/       # Strategy interface, EmaCrossover, RsiReversion, StrategyRegistry
│   ├── backtest/       # BacktestEngine (Bar-by-bar backtest simulation)
│   ├── indicators/     # SMA, EMA, RSI, MACD, ATR, BollingerBands, VWAP
│   ├── challenge/      # FtmoChallengeEvaluator (Discipline score, Risk limits)
│   └── statistics/     # StatisticsCalculator (Sharpe, Sortino, Drawdown, PF, Expectancy)
├── data/
│   ├── local/          # Room AppDatabase, Entities, DAOs
│   └── repository/     # TradingRepository, MarketDataRepository
├── feature/
│   ├── account/        # Virtual account management & summary
│   ├── market/         # Real-time Market Watch, Search, Favorites
│   ├── chart/          # Candlestick chart screen & quick orders
│   ├── trade/          # Virtual order forms, Risk calculator & open positions
│   ├── history/        # Trade Journal & filters
│   ├── replay/         # Historical replay bar-by-bar trading
│   ├── backtest/       # Backtest configuration & instant charts
│   ├── results/        # Results dashboard & performance metrics
│   ├── calendar/       # Monthly trading calendar & daily summaries
│   ├── challenge/      # FTMO challenge limits & discipline score
│   └── settings/       # Data provider settings & security
└── ui/
    ├── components/     # CandlestickChart, EquityCurveChart, CommonCards
    ├── navigation/     # Screen routes & Bottom Navigation
    └── theme/          # Financial dark color scheme & typography
```

---

## How to Build & Run

### Prerequisites
- Android Studio Ladybug / Meerkat or compatible Gradle environment.
- Android SDK API 36 (Minimum API 26).
- Java 11+.

### Build Commands
```bash
# Verify compilation
gradle assembleDebug

# Run unit and Robolectric tests
gradle :app:testDebugUnitTest
```

---

## Configuring Market Data Providers

Market data is abstracted behind `MarketDataProvider` and `HistoricalDataProvider`.

By default, the platform connects to public real-time endpoints (e.g. Binance public crypto quotes for BTCUSD/ETHUSD and standard Forex/Gold spread baselines).

To connect custom market data providers (e.g. TwelveData, Polygon, Interactive Brokers):
1. Add your provider's API key to the **Secrets panel in AI Studio** or `.env` file:
   ```
   MARKET_DATA_API_KEY=your_key_here
   ```
2. Implement `MarketDataProvider` in `com.example.core.market`.
3. Register your provider in `TradeLabApplication.kt`.

Never commit API keys or secret credentials to Git.

---

## License
MIT License.
