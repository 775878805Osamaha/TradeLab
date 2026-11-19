import 'dart:math' as math;

/// Choose legible major price ticks from the *visible provider OHLC range*.
/// This module never manufactures candle data or changes any market price.
class ChartAxisTicks {
  const ChartAxisTicks._();

  static double interval(double minimum, double maximum,
      {int desiredIntervals = 12}) {
    final range = maximum - minimum;
    if (!range.isFinite || range <= 0) return 1;
    final rough = range / desiredIntervals;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor())
        .toDouble();
    final normalized = rough / magnitude;
    const steps = [1.0, 2.0, 4.0, 5.0, 10.0];
    final base = steps.reduce((a, b) =>
        (a - normalized).abs() <= (b - normalized).abs() ? a : b);
    return base * magnitude;
  }

  static Iterable<double> ticks(double minimum, double maximum,
      {int desiredIntervals = 12}) sync* {
    final step = interval(minimum, maximum,
        desiredIntervals: desiredIntervals);
    if (!minimum.isFinite || !maximum.isFinite || maximum <= minimum) return;
    final first = (minimum / step).ceil();
    final last = (maximum / step).floor();
    for (var i = first; i <= last && i < first + 100; i++) {
      yield i * step;
    }
  }

  /// Enough decimals to distinguish adjacent REAL major price ticks.
  ///
  /// A manual TradingView-style vertical ruler zoom can produce forex steps
  /// below 0.0000001. The old hard seven-decimal limit made different price
  /// labels render identically even though their candle y coordinates differed.
  /// Do not round or alter the underlying broker prices; this is display only.
  /// The historical default precision remains unchanged for ordinary ranges.
  static int decimals(double interval) {
    if (!interval.isFinite || interval <= 0) return 7;
    if (interval >= 1) return 2;
    if (interval >= .01) return 3;
    if (interval >= .0001) return 5;
    if (interval >= .000001) return 7;

    // Preserve up to 12 decimal places at extreme zoom. Checking for an
    // integer scaled step also handles non-power-of-ten multiples such as
    // 0.00000025, which needs eight rather than seven digits.
    var scaled = interval * 1e7;
    for (var digits = 7; digits <= 12; digits++) {
      if ((scaled - scaled.roundToDouble()).abs() <= 1e-7) return digits;
      scaled *= 10;
    }
    return 12;
  }
}
