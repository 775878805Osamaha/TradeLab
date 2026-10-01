# Contributing to TradeLab

Thank you for your interest in contributing to TradeLab!

## Contribution Guidelines

1. **Strict Lookahead Protection**:
   - Any strategy, replay, or backtest code must NEVER access future candle or tick data.
   - All indicators and signals must be computed exclusively from historical data available up to the current bar.

2. **No Real Money / No Broker Integration**:
   - TradeLab is strictly for paper trading, backtesting, and market replay. Real order execution or direct brokerage connections are strictly forbidden.

3. **Code Style**:
   - Follow standard Kotlin coding conventions.
   - Use Jetpack Compose for all UI.
   - Use Material 3 theming tokens (`ui/theme/Color.kt`).
   - Keep user-facing strings in `res/values/strings.xml` (Arabic RTL default) and `res/values-en/strings.xml`.

4. **Testing**:
   - Ensure all unit and Robolectric tests pass before submitting changes:
     ```bash
     gradle :app:testDebugUnitTest
     ```
