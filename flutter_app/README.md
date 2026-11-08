# TradeLab — Flutter/Dart UI Preview

This is an **isolated Flutter UI preview**, introduced alongside the original
Kotlin/Jetpack Compose TradeLab Android app. It does not replace, migrate, or
delete the native app, its local Room database or its cTrader login credentials.

## UI identity and screens

- Approved light palette: blue `#2962FF`, bullish green `#26A69A`, bearish red
  `#EF5350`, white backgrounds and compact financial cards; optional dark mode.
- RTL Arabic shell with four bottom tabs: Markets, Chart, Results, Account.
- Chart defaults to **Analysis**. Replay is an in-chart overlay, never a new
  screen. Symbol, timeframe, Japanese candles, Heikin-Ashi, and Range UI
  selectors, indicator preview, line drawing/undo and pinch/pan gestures.
- Markets: search, categories and local favorites. No fabricated live quotes.
- Results: full V3 tabs, date filters and all nine metric labels with blank
  values until actual Room trading results are connected.
- Account: displays cTrader/Binance as *unconnected*. Theme toggle works.

**Important:** Preview candles are deterministic example data and are explicitly
marked as a design fixture. Range mode currently presents only the settings
and preview visualization, **not broker-accurate Range bars**. Production Range
aggregation requires chronological cTrader bid ticks and must be validated
against the existing native Range implementation and backtesting constraints.

## Local run

Requires Flutter SDK / Android SDK:

```bash
cd flutter_app
flutter create --platforms android --project-name tradelab_flutter . --no-pub
flutter pub get
flutter analyze
flutter test test/widget_test.dart
flutter run
```

The GitHub Actions workflow `TradeLab Flutter UI Preview APK` builds a separate
debug APK and produces a chart snapshot as downloadable CI artifacts. Its Android
host has a separate package from the Kotlin app so no existing account data is
overwritten by installing the preview.

## Next integration milestones

1. Introduce authenticated cTrader/Binance repositories, with verified connection
   state and strict distinction between example data and live data.
2. Expose the current native historical storage and trading-ledger domain through
   an API/bridge. Keep ledger balances and order execution disabled until verified.
3. Backfill/cursor-load history; construct Range candles from ordered bid ticks,
   never from OHLC approximations. Replay only reveals bars up to the cut-off.
4. Test Android scrolling/zooming, chart gestures, app startup, offline states,
   RTL, accessibility and cross-screen behavior on a physical device.
