/// Calendar-aware closed-bar boundaries for cTrader Trendbars.
///
/// The gateway returns broker-verified OHLC but may include the active bar.
/// Never expose a still-forming daily, weekly or monthly bar to chart Replay.
/// Boundary times use UTC, the same clock used by cTrader timestamps.
class CTraderClosedBarCutoff {
  const CTraderClosedBarCutoff._();

  static int latestAllowedOpenMs(String timeframe, DateTime now) {
    final utc = now.toUtc();
    final intradayMinutes = switch (timeframe) {
      '1m' => 1,
      '2m' => 2,
      '3m' => 3,
      '5m' => 5,
      '15m' => 15,
      '30m' => 30,
      '1h' => 60,
      '4h' => 240,
      _ => null,
    };
    final int activeOpenMs;
    if (intradayMinutes != null) {
      final intervalMs = intradayMinutes * Duration.millisecondsPerMinute;
      activeOpenMs =
          (utc.millisecondsSinceEpoch ~/ intervalMs) * intervalMs;
    } else {
      final midnight = DateTime.utc(utc.year, utc.month, utc.day);
      final activeOpen = switch (timeframe) {
        '1D' => midnight,
        '1W' => midnight.subtract(
            Duration(days: midnight.weekday - DateTime.monday)),
        '1M' => DateTime.utc(utc.year, utc.month),
        _ => throw ArgumentError.value(timeframe, 'timeframe',
            'Unsupported cTrader timeframe'),
      };
      activeOpenMs = activeOpen.millisecondsSinceEpoch;
    }
    // Open timestamps are inclusive. One millisecond before the active
    // interval starts excludes that bar regardless of provider pagination.
    return activeOpenMs - 1;
  }
}
