import 'dart:math' as math;

import 'chart_symbol_settings.dart';

/// Crosshair labels are presentation of authentic provider UTC timestamps.
/// A BID Range candle can form within milliseconds; minute-only labels would
/// make unrelated candles appear to have identical times.
/// Never infer synthetic spacing between Range candles.
class ChartCrosshairTimeLabel {
  const ChartCrosshairTimeLabel._();

  static String fromSource({
    required int utcTimestampMs,
    required ChartTimeZone zone,
    required bool rangeMode,
  }) {
    if (utcTimestampMs <= 0) {
      throw ArgumentError.value(
          utcTimestampMs, 'utcTimestampMs', 'Missing verified source time');
    }
    final date = zone.displayDate(utcTimestampMs);
    String two(int value) => value.toString().padLeft(2, '0');
    final base = '${two(date.day)}/${two(date.month)} '
        '${two(date.hour)}:${two(date.minute)}';
    if (!rangeMode) return base;
    return '$base:${two(date.second)}.'
        '${date.millisecond.toString().padLeft(3, '0')}';
  }

  /// The label background must cover its MEASURED text width, not the old
  /// hardcoded 75px. Keep its entire rect within the visible candle plot.
  static double badgeWidth({
    required double measuredTextWidth,
    required double plotWidth,
  }) {
    if (!measuredTextWidth.isFinite || measuredTextWidth < 0 ||
        !plotWidth.isFinite || plotWidth <= 0) return 0;
    return math.min(plotWidth, math.max(75.0, measuredTextWidth + 10));
  }
}
