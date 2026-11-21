import 'chart_symbol_settings.dart';

/// Timezone badges follow the timestamp of the rightmost VISIBLE candle.
/// Using the device's current date for historical Replay makes New York
/// display EDT/EST incorrectly on the other side of a DST boundary.
class ChartHistoricalTimeZone {
  const ChartHistoricalTimeZone._();

  static String labelAtVisibleBar({
    required ChartTimeZone zone,
    required List<int> timestampsUtcMs,
    required int lastVisibleIndex,
  }) {
    if (lastVisibleIndex < 0 || lastVisibleIndex >= timestampsUtcMs.length) {
      throw RangeError.index(lastVisibleIndex, timestampsUtcMs);
    }
    final timestamp = timestampsUtcMs[lastVisibleIndex];
    if (timestamp <= 0) {
      throw ArgumentError.value(timestamp, 'timestamp',
          'Cannot label unverified market time');
    }
    return zone.labelAt(DateTime.fromMillisecondsSinceEpoch(
      timestamp, isUtc: true));
  }
}
