import 'dart:math' as math;
import '../data/tradelab_data.dart';

/// Stable price coordinates shared by drawing gestures and chart painting.
/// Drawings are anchored to market prices, not screen-height fractions.
class ChartPriceScale {
  const ChartPriceScale(this.minimum, this.maximum, this.height);
  final double minimum;
  final double maximum;
  final double height;

  factory ChartPriceScale.visible(List<TradeCandle> candles, ChartViewport viewport,
      double width, double height, {
      int topMarginPercent = 8, int bottomMarginPercent = 8}) {
    if (candles.isEmpty) return ChartPriceScale(0, 1, height);
    final (start, end) = viewport.visibleIndices(
      plotWidth: width, candleCount: candles.length);
    if (start >= end) return ChartPriceScale(0, 1, height);
    var minPrice = double.infinity;
    var maxPrice = double.negativeInfinity;
    for (var i = start; i < end; i++) {
      minPrice = math.min(minPrice, candles[i].low);
      maxPrice = math.max(maxPrice, candles[i].high);
    }
    // Margins are actual price-axis viewport space, not a decorative Padding
    // around the canvas. All drawing hit-tests use this same scale.
    final span = math.max(maxPrice - minPrice, maxPrice.abs() * .00001);
    final visibleFraction = (1 - (topMarginPercent + bottomMarginPercent) / 100)
        .clamp(.2, 1.0);
    final fullSpan = span / visibleFraction;
    return ChartPriceScale(
      minPrice - fullSpan * bottomMarginPercent / 100,
      maxPrice + fullSpan * topMarginPercent / 100, height);
  }

  double y(double price) => (maximum - price) / (maximum - minimum) * height;
  double price(double y) => maximum - y / height * (maximum - minimum);
}

/// Price-chart horizontal viewport. Zero means the newest bar is at the right
/// price axis; negative scrolling leaves intentional space after the last bar.
/// Positive scrolling visits historical bars. Independent of Flutter so its
/// gesture mathematics can be unit tested.
class ChartViewport {
  const ChartViewport({this.barWidth = 10, this.scrollBars = 0,
    this.rightMarginBars = 0});

  final double barWidth;
  final double scrollBars;
  /// Permanent right-hand space, measured in actual candle columns. It does
  /// not modify source data, replay count or the historical scroll anchor.
  final double rightMarginBars;

  ChartViewport withRightMarginBars(double bars) => ChartViewport(
    barWidth: barWidth, scrollBars: scrollBars, rightMarginBars: bars);

  static const minBarWidth = 5.0;
  static const maxBarWidth = 30.0;

  double chartX({
    required int index,
    required int candleCount,
    required double plotWidth,
  }) => plotWidth -
      (candleCount - scrollBars - index - .5 + rightMarginBars) * barWidth;

  /// Converts an x-coordinate to the nearest candle index without clamping
  /// future whitespace to the last candle (important for Replay correctness).
  int? indexAt({required double x, required double plotWidth,
      required int candleCount}) {
    if (candleCount <= 0 || x < 0 || x > plotWidth) return null;
    final index = ((x - plotWidth) / barWidth +
        candleCount - scrollBars - .5 + rightMarginBars).round();
    return index < 0 || index >= candleCount ? null : index;
  }

  double get futurePaddingBars => rightMarginBars + math.max(0.0, -scrollBars);

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
        rightMarginBars: rightMarginBars,
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
      rightMarginBars: rightMarginBars,
      scrollBars: _boundedScroll(anchoredScroll, plotWidth, candleCount, width),
    );
  }

  /// Keep the same historical candle under the same x-coordinate after
  /// Range bars are regenerated from newly prepended BID ticks. Range bar
  /// counts and indices can both change when the starting price changes.
  /// This is intentionally separate from the regular gesture pan.
  ChartViewport remapHistoricalAnchor({
    required int oldCount,
    required int oldIndex,
    required int newCount,
    required int newIndex,
  }) {
    if (scrollBars <= 0 || oldCount < 1 || newCount < 1 ||
        oldIndex < 0 || oldIndex >= oldCount ||
        newIndex < 0 || newIndex >= newCount) {
      return this;
    }
    // chartX depends on (candleCount - scrollBars - index).
    // Preserve that expression at the same bar width and plot width.
    final remapped = scrollBars +
        (newCount - oldCount) - (newIndex - oldIndex);
    return ChartViewport(
      barWidth: barWidth,
      rightMarginBars: rightMarginBars,
      scrollBars: remapped.clamp(0.0, (newCount - 1).toDouble()).toDouble(),
    );
  }

  ChartViewport jumpToLatest() => ChartViewport(
    barWidth: barWidth, rightMarginBars: rightMarginBars);

  /// A new broker-closed bar should follow the right edge only when the user
  /// is already at the latest candle. Preserve the visible time anchor both
  /// when inspecting history (positive scroll) and when the user deliberately
  /// leaves whitespace to the right of the final candle (negative scroll).
  ChartViewport afterAppending(int appended) {
    if (appended <= 0 || scrollBars == 0) return this;
    return ChartViewport(
      barWidth: barWidth,
      rightMarginBars: rightMarginBars,
      scrollBars: scrollBars + appended,
    );
  }

  /// Inclusive first and exclusive last candidate indices, with a small
  /// overdraw margin so thin wicks never pop in at the boundaries.
  (int, int) visibleIndices({
    required double plotWidth,
    required int candleCount,
  }) {
    if (candleCount <= 0) return (0, 0);
    final edge = candleCount - scrollBars + rightMarginBars;
    final from = (edge - plotWidth / barWidth - 2).floor().clamp(0, candleCount);
    final to = (edge + 2).ceil().clamp(0, candleCount);
    return (from, math.max(from, to));
  }

  @override
  bool operator ==(Object other) => other is ChartViewport &&
      other.barWidth == barWidth && other.scrollBars == scrollBars &&
      other.rightMarginBars == rightMarginBars;

  @override
  int get hashCode => Object.hash(barWidth, scrollBars, rightMarginBars);
}

/// Only a deliberate one-finger pan can carry momentum into a chart fling.
/// Editing a drawing, pinching, empty history and reduced-motion settings
/// must never trigger a new autonomous scroll.
bool chartShouldFling({
  required double horizontalVelocity,
  required int candleCount,
  required bool multiTouch,
  required bool editingDrawing,
  required bool reducedMotion,
}) => horizontalVelocity.isFinite &&
    horizontalVelocity.abs() >= 180 && candleCount > 1 &&
    !multiTouch && !editingDrawing && !reducedMotion;
