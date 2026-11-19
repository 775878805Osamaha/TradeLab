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

  /// Read the price displayed by the crosshair from the *same* price scale
  /// that paints candles, levels, SL/TP and the right axis. Applying a
  /// separate minimum span (e.g. 0.00001) to only the crosshair label breaks
  /// the on-screen price/line agreement at fine forex zoom levels.
  ///
  /// No broker data is transformed; an invalid scale is not advertised as
  /// a tradable price. Vertical touches outside the plot use its nearest
  /// visible edge.
  double? crosshairPrice(double yPosition) {
    final span = maximum - minimum;
    if (!yPosition.isFinite || !height.isFinite || height <= 0 ||
        !minimum.isFinite || !maximum.isFinite ||
        !span.isFinite || span <= 0) {
      return null;
    }
    return price(yPosition.clamp(0.0, height).toDouble());
  }

  /// A manually adjusted price interval retains its market-price anchors
  /// when the Android chart canvas changes height (e.g. focus mode / Replay).
  ChartPriceScale withHeight(double newHeight) =>
      ChartPriceScale(minimum, maximum, newHeight);

  /// Vertical drag on the RIGHT price scale, independent of time-axis pan.
  /// The price under the user's finger stays at the same y while zooming.
  /// An upward drag magnifies price movement; downward reveals more range.
  /// Pure geometry: no broker OHLC, Replay boundary or drawing is mutated.
  ChartPriceScale dragPriceAxis({
    required double deltaY,
    required double focalY,
  }) {
    final span = maximum - minimum;
    if (!deltaY.isFinite || !focalY.isFinite ||
        !height.isFinite || height <= 0 ||
        !minimum.isFinite || !maximum.isFinite ||
        !span.isFinite || span <= 0 || deltaY == 0) {
      return this;
    }
    final zoomFactor = math.exp(
        (-deltaY.clamp(-120.0, 120.0).toDouble()) / 240.0);
    final minSpan = math.max(1e-9, (maximum.abs() + minimum.abs()) * 1e-11);
    final nextSpan = (span / zoomFactor).clamp(minSpan, 1e15).toDouble();
    if (nextSpan == span) return this;
    final anchorY = focalY.clamp(0.0, height).toDouble();
    final anchorPrice = price(anchorY);
    final aboveFraction = anchorY / height;
    final nextMax = anchorPrice + aboveFraction * nextSpan;
    final nextMin = anchorPrice - (1 - aboveFraction) * nextSpan;
    if (!nextMin.isFinite || !nextMax.isFinite || nextMax <= nextMin) {
      return this;
    }
    return ChartPriceScale(nextMin, nextMax, height);
  }
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

  // Allow a wider continuous zoom than the original 5–30px envelope:
  // users can inspect individual candle structures or a much longer
  // session without artificial tick interpolation. Default stays 10px.
  static const minBarWidth = 3.0;
  static const maxBarWidth = 60.0;

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

  /// Brings the REAL selected Replay candle into the plot without altering
  /// its source index, UTC timestamp, zoom or right-margin preference.
  ///
  /// Very early candles cannot be centered without blank history to the
  /// left, so use the bounded scroll limit to keep them visible at the edge.
  ChartViewport revealHistoricalBar({
    required int index,
    required int candleCount,
    required double plotWidth,
  }) {
    if (index < 0 || index >= candleCount ||
        !plotWidth.isFinite || plotWidth <= 0) {
      return this;
    }
    final wantedX = plotWidth / 2;
    final proposed = candleCount - index - .5 + rightMarginBars -
        (plotWidth - wantedX) / barWidth;
    return ChartViewport(
      barWidth: barWidth,
      rightMarginBars: rightMarginBars,
      scrollBars: _boundedScroll(
        proposed, plotWidth, candleCount, barWidth),
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

/// Resolves a crosshair position to one source candle and its exact x.
/// The price/time markers must not claim a different candle than the vertical
/// crosshair line when bars become as narrow as 3px on an Android phone.
///
/// Whitespace to the right of the last broker/Replay candle stays whitespace:
/// no synthetic future index or timestamp is returned.
class ChartCrosshairSnap {
  const ChartCrosshairSnap._();

  static ({double x, int? index}) resolve({
    required ChartViewport viewport,
    required double touchX,
    required double plotWidth,
    required int candleCount,
  }) {
    if (!touchX.isFinite || !plotWidth.isFinite || plotWidth <= 0) {
      return (x: 0, index: null);
    }
    final x = touchX.clamp(0.0, plotWidth).toDouble();
    final index = viewport.indexAt(
      x: x, plotWidth: plotWidth, candleCount: candleCount);
    if (index == null) return (x: x, index: null);
    final centerX = viewport.chartX(
      index: index, candleCount: candleCount, plotWidth: plotWidth);
    if (!centerX.isFinite || centerX < 0 || centerX > plotWidth) {
      // The closest candle center is beyond the visible clip. Do not pin a
      // label to an off-screen source candle or invent a visible timestamp.
      return (x: x, index: null);
    }
    return (x: centerX, index: index);
  }
}

/// Tracks one continuous touch session independently from the chart's OHLC.
 /// When a second finger joins after a pan, the pinch is rebased on the
 /// *current* viewport (not the original touch-down). The first two-finger
 /// update and the first one-finger update after lifting a finger are ignored:
 /// both are pointer-centroid changes, not deliberate chart movement.
class ChartTouchGesture {
  ChartViewport? _pinchOrigin;
  double _pinchOriginFocalX = 0;
  double _pinchOriginScale = 1;
  bool _pinching = false;

  bool hadMultiTouch = false;
  bool ignoredPointerTransition = false;
  double horizontalTravel = 0;

  ChartViewport update({
    required ChartViewport viewport,
    required int pointerCount,
    required double focalX,
    required double scale,
    required double deltaX,
    required double plotWidth,
    required int candleCount,
  }) {
    ignoredPointerTransition = false;
    if (pointerCount > 1) {
      hadMultiTouch = true;
      if (!_pinching) {
        _pinching = true;
        _pinchOrigin = viewport;
        _pinchOriginFocalX = focalX;
        _pinchOriginScale = scale.isFinite && scale > 0 ? scale : 1;
        ignoredPointerTransition = true;
        return viewport;
      }
      if (!scale.isFinite || scale <= 0 || !focalX.isFinite) {
        return viewport;
      }
      return _pinchOrigin!.pinch(
        scale: scale / _pinchOriginScale,
        initialFocalX: _pinchOriginFocalX,
        currentFocalX: focalX,
        plotWidth: plotWidth,
        candleCount: candleCount,
      );
    }
    if (_pinching) {
      _pinching = false;
      _pinchOrigin = null;
      ignoredPointerTransition = true;
      return viewport;
    }
    if (pointerCount != 1 || !deltaX.isFinite) return viewport;
    horizontalTravel += deltaX.abs();
    return viewport.pan(
      deltaX: deltaX, plotWidth: plotWidth, candleCount: candleCount,
    );
  }
}

/// Only a deliberate one-finger pan can carry momentum into a chart fling.
/// Editing a drawing, pinching, empty history and reduced-motion settings
/// must never trigger a new autonomous scroll.
bool chartShouldFling({
  required double horizontalVelocity,
  required double horizontalTravel,
  required int candleCount,
  required bool multiTouch,
  required bool editingDrawing,
  required bool reducedMotion,
}) => horizontalVelocity.isFinite && horizontalTravel.isFinite &&
    horizontalVelocity.abs() >= 180 && horizontalTravel >= 14 &&
    candleCount > 1 &&
    !multiTouch && !editingDrawing && !reducedMotion;

/// Only the candle painter reads the viewport dynamically during a repaint.
/// Other viewport-dependent layers use immutable painter/position snapshots
/// from build(), so they must be rebuilt when visible. In particular, Replay
/// selection, price rectangles and practice trade levels cannot be left
/// behind while the candles move underneath them.
bool chartCanUsePaintOnlyViewportUpdate({
  required bool selectingReplayStart,
  required bool crosshairVisible,
  required bool movingDrawing,
  required bool visiblePriceRectangles,
  // Enable only for rectangles bound to chart's shared repaint signal and
  // dynamic viewport/auto-scale, never for an unbound snapshot painter.
  bool priceRectanglesFollowViewport = false,
  required bool replayTradeLevelsVisible,
  // Opt in only when the practice overlay is wired to the SAME viewport
  // notifier and live price scale as the chart painter.
  bool replayTradeLevelsFollowViewport = false,
}) =>
    !selectingReplayStart &&
    !crosshairVisible &&
    !movingDrawing &&
    (!visiblePriceRectangles || priceRectanglesFollowViewport) &&
    (!replayTradeLevelsVisible || replayTradeLevelsFollowViewport);
