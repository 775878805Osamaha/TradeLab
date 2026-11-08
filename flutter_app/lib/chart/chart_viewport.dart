import 'dart:math' as math;

/// Price-chart horizontal viewport. Zero means the newest bar is at the right
/// price axis; negative scrolling leaves intentional space after the last bar.
/// Positive scrolling visits historical bars. Independent of Flutter so its
/// gesture mathematics can be unit tested.
class ChartViewport {
  const ChartViewport({this.barWidth = 10, this.scrollBars = 0});

  final double barWidth;
  final double scrollBars;

  static const minBarWidth = 5.0;
  static const maxBarWidth = 30.0;

  double chartX({
    required int index,
    required int candleCount,
    required double plotWidth,
  }) => plotWidth - (candleCount - scrollBars - index - .5) * barWidth;

  double get futurePaddingBars => math.max(0.0, -scrollBars);

  double _boundedScroll(double proposed, double plotWidth, int candleCount,
      double newWidth) {
    final forwardSpace = math.max(1.0, plotWidth / newWidth * .68);
    final oldest = math.max(0, candleCount - 1).toDouble();
    return proposed.clamp(-forwardSpace, oldest).toDouble();
  }

  ChartViewport pan({
    required double deltaX,
    required double plotWidth,
    required int candleCount,
  }) => ChartViewport(
        barWidth: barWidth,
        scrollBars: _boundedScroll(
          scrollBars + deltaX / barWidth, plotWidth, candleCount, barWidth),
      );

  /// Keeps the sample under the initial pinch focal point anchored while
  /// zooming. Moving both fingers together also pans the chart naturally.
  ChartViewport pinch({
    required double scale,
    required double initialFocalX,
    required double currentFocalX,
    required double plotWidth,
    required int candleCount,
  }) {
    final width = (barWidth * scale).clamp(minBarWidth, maxBarWidth).toDouble();
    final anchoredScroll = scrollBars +
        (plotWidth - initialFocalX) * (1 / barWidth - 1 / width) +
        (currentFocalX - initialFocalX) / width;
    return ChartViewport(
      barWidth: width,
      scrollBars: _boundedScroll(anchoredScroll, plotWidth, candleCount, width),
    );
  }

  ChartViewport jumpToLatest() => ChartViewport(barWidth: barWidth);

  /// Inclusive first and exclusive last candidate indices, with a small
  /// overdraw margin so thin wicks never pop in at the boundaries.
  (int, int) visibleIndices({
    required double plotWidth,
    required int candleCount,
  }) {
    if (candleCount <= 0) return (0, 0);
    final edge = candleCount - scrollBars;
    final from = (edge - plotWidth / barWidth - 2).floor().clamp(0, candleCount);
    final to = (edge + 2).ceil().clamp(0, candleCount);
    return (from, math.max(from, to));
  }

  @override
  bool operator ==(Object other) => other is ChartViewport &&
      other.barWidth == barWidth && other.scrollBars == scrollBars;

  @override
  int get hashCode => Object.hash(barWidth, scrollBars);
}
