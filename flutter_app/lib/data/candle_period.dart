/// Returns the exclusive close boundary of a candle that opened at [openMs].
/// All arithmetic uses UTC so local daylight-saving changes cannot shift bars.
int candlePeriodEndMs(int openMs, String timeframe) {
  if (timeframe == '1M') {
    final open = DateTime.fromMillisecondsSinceEpoch(openMs, isUtc: true);
    return DateTime.utc(open.year, open.month + 1).millisecondsSinceEpoch;
  }
  final minutes = switch (timeframe) {
    '1m' => 1, '3m' => 3, '5m' => 5, '15m' => 15,
    '30m' => 30, '1h' => 60, '4h' => 240,
    '1D' => 1440, '1W' => 10080,
    _ => throw ArgumentError.value(timeframe, 'timeframe', 'Unsupported candle period'),
  };
  return openMs + minutes * 60000;
}
