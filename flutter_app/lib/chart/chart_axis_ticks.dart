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
    yield* ticksWithStep(minimum, maximum, step: step);
  }

  /// The candle canvas already computes [step] for tick importance and
  /// decimal precision. Reuse that exact step for the visible labels instead
  /// of performing the same log/pow/step search a second time each frame.
  /// All tick coordinates, old rounding rules and the 100-label guard stay
  /// identical to [ticks].
  static Iterable<double> ticksWithStep(
      double minimum, double maximum, {required double step}) sync* {
    if (!minimum.isFinite || !maximum.isFinite || maximum <= minimum ||
        !step.isFinite || step <= 0) return;
    final first = (minimum / step).ceil();
    final last = (maximum / step).floor();
    for (var i = first; i <= last && i < first + 100; i++) {
      yield i * step;
    }
  }

  /// Human-readable logarithmic major prices. True log rulers use 1-2-5
  /// steps per decade (or fewer decades for a broad range); near-linear
  /// zooms keep the familiar decimal tick precision from the linear axis.
  /// These are LABEL values only and never generate market candles/quotes.
  static Iterable<double> logarithmicTicks(
      double minimum, double maximum) sync* {
    if (!minimum.isFinite || !maximum.isFinite ||
        minimum <= 0 || maximum <= minimum) return;
    final firstLog = math.log(minimum) / math.ln10;
    final lastLog = math.log(maximum) / math.ln10;
    final decades = lastLog - firstLog;
    if (!decades.isFinite || decades <= 0) return;
    if (decades < .35) {
      yield* ticks(minimum, maximum, desiredIntervals: 9);
      return;
    }
    final firstExponent = firstLog.floor();
    final lastExponent = lastLog.ceil();
    final stride = math.max(1,
        ((lastExponent - firstExponent + 1) / 12).ceil());
    var count = 0;
    for (var exponent = firstExponent;
        exponent <= lastExponent && count < 60; exponent += stride) {
      final base = math.pow(10, exponent).toDouble();
      if (!base.isFinite || base <= 0) continue;
      final multiples = stride == 1 ? const <double>[1, 2, 5] :
          const <double>[1];
      for (final multiplier in multiples) {
        final tick = base * multiplier;
        if (tick.isFinite && tick >= minimum && tick <= maximum) {
          yield tick;
          count++;
        }
      }
    }
  }

  /// Pixel-aware target count for a narrow Android price ruler. A fixed
  /// twelve labels over a compact 90dp Replay pane makes 14dp text overlap.
  /// Never request more labels than 22dp vertical spacing can support.
  static int intervalsForHeight(double plotHeight) {
    if (!plotHeight.isFinite || plotHeight <= 0) return 2;
    return (plotHeight / 22).floor().clamp(2, 12).toInt();
  }

  /// One geometry pass for regular, inverted and logarithmic ruler ticks.
  /// Used *before* painting both text and grid; hidden ticks cannot leave
  /// unpaired lines on the source-price scale. The transform always comes
  /// from the same ChartPriceScale that draws real candles and annotations.
  static Iterable<double> spacedByPixels(
      Iterable<double> ticks, {
      required double Function(double) y,
      required double plotHeight,
      double minLabelGap = 19,
    }) sync* {
    if (!plotHeight.isFinite || plotHeight <= 0 ||
        !minLabelGap.isFinite || minLabelGap < 0) return;
    double? previousY;
    for (final value in ticks) {
      if (!value.isFinite) continue;
      final pixel = y(value);
      if (!pixel.isFinite || pixel < 9 || pixel > plotHeight - 9) {
        continue;
      }
      if (previousY != null &&
          (pixel - previousY).abs() < minLabelGap) continue;
      previousY = pixel;
      yield value;
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
    if (scaled < 1e-7) return 12;
    for (var digits = 7; digits <= 12; digits++) {
      if ((scaled - scaled.roundToDouble()).abs() <= 1e-7) return digits;
      scaled *= 10;
    }
    return 12;
  }
}
