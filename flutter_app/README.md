# TradeLab — Flutter/Dart integration preview

This is an **isolated Flutter UI preview**, introduced alongside the original
Kotlin/Jetpack Compose TradeLab Android app. It does not replace, migrate, or
delete the native app, its local Room database or its cTrader login credentials.

## UI identity and screens

- Approved light palette: blue `#2962FF`, bullish green `#26A69A`, bearish red
  `#EF5350`, white backgrounds and compact financial cards; optional dark mode.
- RTL Arabic shell with five bottom tabs: Markets, Chart, Results,
  **Trading Lab (مختبر التداول)**, Account. Its risk overview, standalone
  position-size calculator and Replay analysis share the approved Flutter
  theme without reducing the chart area.
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
- Paper trading risk: optional user-specified SL/TP and maximum USD loss are
  required by the new order sheet. A deterministic local gate sizes base-asset
  units against existing open notional, available deposited cash and selected
  risk limits (the optional daily cap resets at UTC midnight), then rechecks
  the same quote inside a controller-wide write lock before recording.
  Daily risk also reserves known stop risk on positions carried over from
  previous UTC days. The Trading Lab calculator additionally exposes optional
  aggregate notional, daily trade-count and minimum reward/risk limits; they
  are **session calculations**, not persistent policies on the order sheet.
  New risk levels survive SQLite v1-to-v2 migration; old positions are preserved
  with unknown levels. These are **informational** stops/targets, not automatic
  broker orders, and legacy direct journal-entry APIs remain distinct.
- Replay research: a compact analysis action inside the existing Replay toolbar
  simulates 1,000 seeded OHLC paths from **only revealed historical bars**.
  It refuses synthetic previews and Range, requires at least 30 completed
  provider candles, and is explicitly an in-sample scenario
  distribution, **not** a forecast or verified out-of-sample backtest.
  The user may supply an estimated *round-trip cost per base unit in the
  symbol's quote currency* (spread, converted fees and slippage combined).
  Only then are estimated net R and net percentile ranges shown alongside
  gross values. No broker-derived transaction costs are implied.
  A separate tested observed-trade evaluator uses the next completed bar's
  open after a signal (never the signal close), conservative same-bar
  stop-first ordering and adverse-gap stop fills. It is domain logic for a
  future Replay journal UI and does not send or record actual orders.
- Trading Lab: the overview reads actual local ledger balance, committed open
  notional, known stop-loss exposure, unknown-risk positions and UTC daily
  realized P/L; it never represents these as cTrader account balances. The
  calculator fetches fresh cTrader/Binance BID/ASK on explicit request and
  evaluates the same risk engine as the order sheet, without saving rules or
  opening trades. The Replay panel uses a frozen on-demand snapshot of the
  currently revealed, completed provider candles only. Its snapshot is
  invalidated on local journal account changes. Navigating away pauses Replay
  playback but preserves its chart cursor, and the chart remains mounted.
  A chart-to-Lab capture uses a bounded read-only view of its immutable,
  completed-candle history generation; capturing a 100k-bar cursor does not
  duplicate that history. New provider pages replace the source generation,
  leaving already captured snapshots stable until refreshed. This is an
  in-memory snapshot optimization, not persistent market-data caching.
- Observed Replay signals: a separate Lab sub-tab records a hypothetical
  long/short signal at the most recently revealed completed source candle.
  The signal is anchored to that candle's UTC timestamp so loading older
  history does not move it. Returning from the chart refreshes the frozen
  snapshot, and the trade's pending/open/stopped/targeted state is recalculated
  strictly from currently revealed OHLC. Execution is modeled at next-bar
  open, same-bar stop/target ambiguity favors the stop, and invalid next-open
  gaps fail explicitly. A recorded optional round-trip cost travels with the
  signal and adjusts its estimated net R as the cursor advances, without
  modifying the entry or stop/target outcome. Signals fail closed if any
  component of their original OHLC candle is revised by the data source.
  The evaluator validates candles as they are consumed and stops at the
  historical exit bar; it does not allocate a post-signal OHLC copy or scan
  later candles once an outcome is resolved, even with a 100k+ chart history.
  Live-device profiling is still required to quantify any frame-time gains.
  Gross and net R are illustrative, not P/L in a real account.
  Signals are session-only; they are not stored in the paper ledger and
  cannot create broker orders.
- Replay session log: a third Lab research sub-tab groups up to 100 manually
  recorded, chronological, non-overlapping observed signals. It only accepts
  another signal after the prior trade has reached its stop or target on
  *revealed* provider candles and after that trade's exit bar. The summary
  shows resolved/pending/open/unavailable counts, gross cumulative R, an
  estimated net R total **only if all resolved signals supply round-trip
  costs**, resolved-trade hit rate and gross R drawdown. These statistics do
  not represent dollars, equity, independent trade samples or out-of-sample
  performance. Rewinding Replay hides future outcomes; source revisions and
  account changes fail closed. Changing account, symbol or timeframe clears
  the scoped log. A separate confirmation is required to clear it manually;
  no study data is written to SQLite or sent to a broker.
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
flutter test
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

The separate `Verify TradeLab Flutter Lab APK (no release)` workflow runs all
non-golden Flutter tests, static analysis, release APK signing validation and
an Android 13 emulator install/launch check. It uploads a **test-only artifact**
on the feature branch; it does not publish a GitHub Release or merge into main.
This validation does not verify live broker credentials, cTrader market data,
or physical-device touch performance.

## Next integration milestones

1. Deploy the additive gateway OAuth route, then perform a read-only cTrader
   login and real XAUUSD/forex candle smoke test on a device.
2. Expose the current native historical storage and trading-ledger domain through
   an API/bridge. Keep ledger balances and order execution disabled until verified.
3. Stress-test time-series pagination and broker Range semantics; replay only
   reveals bars up to the cut-off.
4. Profile Android scrolling/zooming, chart gestures, app startup, offline states,
   RTL, accessibility and cross-screen behavior on a physical device.
