# TradeLab — Flutter/Dart integration preview

This is an **isolated Flutter UI preview**, introduced alongside the original
Kotlin/Jetpack Compose TradeLab Android app. It does not replace, migrate, or
delete the native app, its local Room database or its cTrader login credentials.

## UI identity and screens

- Approved light palette: blue `#2962FF`, bullish green `#26A69A`, bearish red
  `#EF5350`, white backgrounds and compact financial cards; optional dark mode.
- RTL Arabic shell with four bottom tabs: Markets, Chart, Results, Account.
- Chart defaults to **Analysis**. Replay is an in-chart overlay, never a new
  screen. Symbol, timeframe, Japanese candles, Heikin-Ashi, and Range UI
  selectors, indicator preview, line drawing/undo, a long-press crosshair,
  focal-point-preserving pinch, historical drag and optional right-hand whitespace
  that allows the latest candle to move to the chart center.
- Markets: search, categories, favorites and explicit Binance public-price refresh.
- cTrader integration: optional per-user browser OAuth with a **separate**
  `tradelabflutter://` Android callback. Session is stored using encrypted secure
  storage, and the chosen broker account is read-only. The existing Kotlin
  `tradelab://` callback remains unchanged.
- Actual historical candles: validated cTrader broker gateway for gold/forex
  (requires login), Binance for BTC/ETH. History can page backwards; errors
  never silently substitute example prices. Unclosed Binance candles are hidden.
- Range when linked: builds from chronological actual cTrader BID ticks and
  broker-provided decimal point precision; incomplete tick responses fail closed.
- Drawing levels are anchored to **price**, selectable, draggable, undoable and
  individually deletable, rather than attached to screen coordinates.
- Broker symbol IDs are cached per account and invalidated on account changes,
  reducing redundant symbol-list requests while paging. Live chart loading,
  empty-data and older-page retry states are visible instead of appearing as a
  blank chart. Heikin-Ashi smoothing is reused until the source candles change.
- Results: full V3 tabs, date filters and all nine metric labels with blank
  values until actual Room trading results are connected.
- Account: account login and switcher, Binance refresh, connection status and
  theme toggle. Results remain unlinked until Room migration is verified.

**Important:** Until a per-user cTrader OAuth session is successfully authorized,
the default XAUUSD chart still displays a clearly labeled **synthetic design
fixture**. Once signed in, a broker error results in an error state, *never*
synthetic fallback. In disconnected Range preview only, synthetic tick data are
still used and labeled as preview. Real Range has no OHLC shortcuts. Production
range-bar semantics must still be compared with a supported broker reference.

The backend's additive `client=flutter` OAuth callback change must be deployed
to the configured gateway *before* the separate Flutter Android callback can
work. The repository/CI change alone does **not** deploy Vercel, configure
credentials or prove a successful authenticated live session.

## Local run

Requires Flutter SDK / Android SDK:

```bash
cd flutter_app
flutter create --platforms android --project-name tradelab_flutter . --no-pub
python3 tool/configure_android_host.py
flutter pub get
flutter analyze
flutter test test/widget_test.dart
flutter run
```

The GitHub Actions workflow `TradeLab Flutter UI Preview APK` builds a separate
optimized AOT preview APK (debug-key signed, **not** a production key), verifies
its ZIP structure and Android signing, installs and launches it in an Android
13 emulator, publishes a
**directly downloadable APK** as a GitHub prerelease, and produces a chart
snapshot as a CI artifact. Download the `.apk` asset from GitHub Releases,
**not** the GitHub Actions ZIP artifact. Its Android
host has a separate package from the Kotlin app so no existing account data is
overwritten by installing the preview.

## Next integration milestones

1. Deploy the additive gateway OAuth route, then perform a read-only cTrader
   login and real XAUUSD/forex candle smoke test on a device.
2. Expose the current native historical storage and trading-ledger domain through
   an API/bridge. Keep ledger balances and order execution disabled until verified.
3. Stress-test time-series pagination and broker Range semantics; replay only
   reveals bars up to the cut-off.
4. Profile Android scrolling/zooming, chart gestures, app startup, offline states,
   RTL, accessibility and cross-screen behavior on a physical device.
