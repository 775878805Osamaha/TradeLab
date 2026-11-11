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

  static int decimals(double interval) => interval >= 1 ? 2
      : interval >= .01 ? 3 : interval >= .0001 ? 5 : 7;
}
