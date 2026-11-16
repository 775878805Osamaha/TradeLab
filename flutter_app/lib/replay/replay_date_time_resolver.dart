import '../chart/chart_symbol_settings.dart';

/// Converts user-selected wall-clock dates back to authenticated UTC market
/// timestamps using the chart's CURRENT configured timezone.
///
/// New York can have two real UTC instants for a clock-time at autumn DST
/// rollback. Caller MUST ask the user to choose rather than guessing.
/// Spring-forward clock times with no real instant return an empty list.
/// These are timestamp conversions only: never fabricates market candles.
class ReplayDateTimeResolver {
  const ReplayDateTimeResolver._();

  static DateTime displayWallTime(ChartTimeZone zone, int utcMs) =>
      zone.displayDate(utcMs);

  /// An ordered list of UTC instants corresponding to the selected chart
  /// wall-clock time. Empty for an impossible local time.
  static List<int> utcCandidates({
    required ChartTimeZone zone,
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) {
    final wall = DateTime.utc(year, month, day, hour, minute);
    if (wall.year != year || wall.month != month || wall.day != day ||
        wall.hour != hour || wall.minute != minute) {
      return const [];
    }
    switch (zone) {
      case ChartTimeZone.utc:
        return [wall.millisecondsSinceEpoch];
      case ChartTimeZone.device:
        final local = DateTime(year, month, day, hour, minute);
        if (local.year != year || local.month != month || local.day != day ||
            local.hour != hour || local.minute != minute) {
          return const [];
        }
        return [local.toUtc().millisecondsSinceEpoch];
      case ChartTimeZone.newYork:
        final results = <int>[];
        // The exact New York DST implementation is centralized in
        // ChartTimeZone; use both documented 4h/5h offsets and roundtrip
        // through it instead of assuming a present-day offset.
        for (final hours in [4, 5]) {
          final utcMs = wall.add(Duration(hours: hours)).millisecondsSinceEpoch;
          final converted = zone.displayDate(utcMs);
          if (converted.year == year &&
              converted.month == month &&
              converted.day == day &&
              converted.hour == hour &&
              converted.minute == minute) {
            results.add(utcMs);
          }
        }
        return results;
    }
  }
}
