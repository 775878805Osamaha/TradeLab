# Flutter chart, Replay and Range validation

This document applies to `flutter_app/`, not the legacy Kotlin app.

## Verified-source rules

- cTrader/forex and gold: only broker-authenticated OHLC and BID tick data.
- Binance/crypto: only the supported public crypto instruments.
- Intraday cTrader bars are bounded by the current UTC period opening.
- For daily, weekly and monthly broker bars, use conservative request cutoffs
  that account for nominal bar openings shortly before UTC day/week/month
  boundaries (e.g. forex sessions aligned to 17:00 New York). This may withhold
  just-closed bars briefly; exact broker closure still needs live verification.
- Calendar-frame cTrader cache keys have a separate `broker-closed-v2` namespace.
  Previous potentially unclosed D1/W1/MN1 records remain on disk but are not
  trusted for Replay; intraday cached candles are unaffected.
- Never populate chart gaps with synthetic price history.
- Do not compare Range bar shapes with a screenshot alone. Its broker BID tick
  sequence, price distance, decimal precision, session start and timezone must
  match the reference. The current `RangeBarBuilder` is a reference
  price-distance algorithm and does **not** claim TradingView parity.

## Isolated Replay training

- Tap Replay on a chart with verified source candles. The chart stays in place.
- Practice tickets are local-only and cannot open broker or paper-journal orders.
- A ticket enters at the latest **revealed raw close**; Heikin-Ashi display
  cannot turn its synthetic average into an execution price.
- SL/TP is evaluated only when **subsequent** candles become visible.
- If SL and TP both lie inside one bar, SL wins (conservative ambiguity).
- Seeking backward removes any practice trade that was entered later and
  reopens trades that exited later. Archives are updated accordingly.
- For Range, the latest, still-forming BID bar stays visible on the live
  chart but is excluded from Replay's executable bar count, including after
  loading older ticks. A single verified tick is not a completed Range bar.
- For Range, seeking back through already loaded history is supported; while a
  practice session has trade records, loading an older BID origin is disabled
  to avoid silently reassigning a trade to different recomputed Range bars.
- Practice P&L is **price difference times quantity**, not dollars or a broker
  contract-size estimate. It is not live account equity.
- Archive is stored in a separate `tradelab_replay_training.db`. No broker
  access token is saved there. Exiting Replay preserves the queued final
  snapshot; closing the screen later does not replace it with an empty session.
  Pause and end-of-playback also flush the current cursor.

## Automated tests

```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test test/ctrader_closed_bar_cutoff_test.dart \
  test/replay_training_session_test.dart \
  test/replay_training_archive_test.dart \
  test/replay_training_widget_test.dart \
  test/replay_training_order_dialog_test.dart \
  test/chart_frame_profiler_test.dart \
  test/range_bar_timeline_test.dart \
  test/chart_viewport_test.dart
```

Android device/emulator smoke:

```bash
flutter test integration_test/replay_device_smoke_test.dart -d <device-id>
```

This smoke confirms the unlinked state and that Replay does not reveal
unverified data. A live authenticated cTrader scenario must be verified on a
device with the user's account. Never use private tokens in CI fixtures.

## Native SQLite journal verification (manual Android)

The source-level regression suite includes `test/paper_journal_sqlite_test.dart`
with `sqflite_common_ffi` on Linux. It verifies the real SQL schema, reopen,
double-close safety and account isolation, but it **cannot** prove Android
plugin behavior.

A separate, manual-only integration scenario verifies the Android `sqflite`
plugin and the actual TradeLab Results tab:

```bash
cd flutter_app
flutter pub get
flutter test integration_test/paper_journal_device_test.dart -d <android-device>
```

The device test uses `tradelab_paper_android_smoke_<unique>.db`, **never** the
production `tradelab_flutter_paper_v1.db`. It creates a local deposit and a
practice trade, closes the trade, tears down the app widget and SQLite handle,
reopens the database in a new controller, and checks that saved P&L returns
in Results for account 101 but not account 202. It deletes only its temporary
test database at the end. It never logs in to cTrader or submits broker orders.

Rebuilding the app widget and reopening SQLite verifies native persistence,
**not** a full Android process kill, phone reboot, old Kotlin Room migration
or production-APK upgrade. Those remain manual device acceptance checks.
Record the device, OS, APK commit, observed P&L and test output. Do not mark
these checks as passed unless device logs exist.

## Frame performance measurements (physical Android)

```bash
cd flutter_app
flutter run --profile --dart-define=TRADELAB_PROFILE_CHART=true
adb logcat | grep TRADELAB_CHART_FRAME_METRICS
```

The opt-in profiler reports rolling samples of 120 frames: build p50/p95,
raster p95, frame p95/p99, and counts exceeding 8.33/16.67ms. Samples have
no prices, broker IDs or access credentials. They include Flutter frames while
ChartScreen is mounted, so measure **one interaction per session**.

Recommended comparable runs:

1. 10k, 50k and 100k cached verified time candles;
2. one-finger drag + deceleration and two-finger focal-point pinch;
3. 5-minute/12-hour BID Range paging and chart load;
4. Replay at 1× and 8×, forward and backward seeks;
5. the same scenarios on a midrange physical phone and emulator.

Record the commit, Android version, hardware refresh rate, Flutter version,
frame metrics and memory before/after any optimization. Do not claim a fix is
faster without before/after measurements.

## Not yet verified

- exact proprietary TradingView Range parity with broker reference ticks;
- authenticated cTrader OAuth and runtime market feed on a real device;
- workload-specific performance budgets and device frame-timing results;
- full migrated Kotlin trading ledger parity and production-ready APK.
