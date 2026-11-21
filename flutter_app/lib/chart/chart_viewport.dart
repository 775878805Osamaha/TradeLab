import 'dart:math' as math;
import '../data/tradelab_data.dart';
import 'chart_price_text_formatter.dart';

/// Presentation of verified prices on the right ruler; market candle values,
/// drawing anchors, and trading calculations remain in ORIGINAL price units.
enum ChartPriceReferenceMode { price, percent, indexed100 }

/// Stable price coordinates shared by drawing gestures and chart painting.
/// Drawings are anchored to market prices, not screen-height fractions.
class ChartPriceScale {
  const ChartPriceScale(this.minimum, this.maximum, this.height, {
    this.sourceCandles,
    this.sourceMinimum,
    this.sourceMaximum,
    this.sourceVisibleStart,
    this.sourceVisibleEnd,
    this.logarithmic = false,
    this.inverted = false,
    this.referenceMode = ChartPriceReferenceMode.price,
    this.referencePrice,
  });
  final double minimum;
  final double maximum;
  final double height;
  /// Applies logarithmic coordinates to market prices without altering OHLC.
  /// The scale remains linear for nonpositive ranges (log is undefined).
  final bool logarithmic;
  /// Inverted TradingView price ruler: higher source prices paint lower on
  /// screen; the underlying OHLC and source candle indices are unchanged.
  final bool inverted;
  /// Relative ruler modes only normalize labels; all y(price)/price(y)
  /// transforms still operate on real market prices. The base is the first
  /// verified visible candle close (never an unrevealed Replay candle).
  final ChartPriceReferenceMode referenceMode;
  final double? referencePrice;
  bool get usesRelativeScale => !logarithmic &&
      referenceMode != ChartPriceReferenceMode.price &&
      referencePrice != null && referencePrice!.isFinite &&
      referencePrice! > 0;

  double axisValue(double marketPrice) {
    if (!usesRelativeScale) return marketPrice;
    final indexed = marketPrice / referencePrice! * 100;
    return referenceMode == ChartPriceReferenceMode.percent
        ? indexed - 100 : indexed;
  }

  double marketPriceForAxisValue(double axisValue) {
    if (!usesRelativeScale) return axisValue;
    return referencePrice! * (referenceMode == ChartPriceReferenceMode.percent
        ? 1 + axisValue / 100 : axisValue / 100);
  }

  String axisLabel(double marketPrice, int digits) {
    final display = axisValue(marketPrice);
    if (!display.isFinite) return '—';
    // Reuse the existing thousands-separator and decimal presentation for
    // Regular and LOG; adding relative modes must not regress older charts.
    final value = ChartPriceTextFormatter.price(
        display, digits.clamp(0, 12).toInt());
    return usesRelativeScale && referenceMode == ChartPriceReferenceMode.percent
        ? '$value%' : value;
  }

  bool get usesLogarithmic => logarithmic &&
      minimum.isFinite && maximum.isFinite &&
      minimum > 0 && maximum > minimum && height.isFinite && height > 0;

  // Verified unpadded extrema are calculated in the same visible-OHLC pass
  // that constructs automatic price geometry. They are distinct from the
  // padded minimum/maximum used for drawing coordinates. Null for a manual
  // ruler scale, empty/offscreen source or free-standing scale.
  final List<TradeCandle>? sourceCandles;
  final double? sourceMinimum;
  final double? sourceMaximum;
  final int? sourceVisibleStart;
  final int? sourceVisibleEnd;

  factory ChartPriceScale.visible(List<TradeCandle> candles, ChartViewport viewport,
      double width, double height, {
      int topMarginPercent = 8, int bottomMarginPercent = 8,
      bool logarithmic = false, bool inverted = false,
      ChartPriceReferenceMode referenceMode = ChartPriceReferenceMode.price}) {
    if (candles.isEmpty) {
      return ChartPriceScale(0, 1, height, inverted: inverted);
    }
    final (start, end) = viewport.visibleIndices(
      plotWidth: width, candleCount: candles.length);
    if (start >= end) {
      return ChartPriceScale(0, 1, height, inverted: inverted);
    }
    var minPrice = double.infinity;
    var maxPrice = double.negativeInfinity;
    for (var i = start; i < end; i++) {
      minPrice = math.min(minPrice, candles[i].low);
      maxPrice = math.max(maxPrice, candles[i].high);
    }
    // Percent/Indexed 100 use the FIRST VISIBLE SOURCE CANDLE CLOSE.
    // It is already in the Replay prefix, and is updated when the user pans
    // history or a genuine market-source list is replaced.
    final baseClose = candles[start].close;
    final safeReference = !logarithmic && baseClose.isFinite &&
        baseClose > 0 ? baseClose : null;
    final safeReferenceMode = safeReference == null
        ? ChartPriceReferenceMode.price : referenceMode;
    // Margins are actual price-axis viewport space, not a decorative Padding
    // around the canvas. All drawing hit-tests use this same scale.
    final span = math.max(maxPrice - minPrice, maxPrice.abs() * .00001);
    final visibleFraction = (1 - (topMarginPercent + bottomMarginPercent) / 100)
        .clamp(.2, 1.0);
    final fullSpan = span / visibleFraction;
    // The physical TOP and BOTTOM margins swap when the ruler is inverted:
    // the minimum price is at the top, not the maximum.
    final lowerMarginPercent =
        inverted ? topMarginPercent : bottomMarginPercent;
    final upperMarginPercent =
        inverted ? bottomMarginPercent : topMarginPercent;
    // A log axis allocates margins in logarithmic *price* coordinates. The
    // source low/high stays unchanged, and an all-nonpositive verified series
    // falls back to linear instead of painting NaN / synthetic market data.
    if (logarithmic && minPrice > 0 && maxPrice > 0 &&
        minPrice.isFinite && maxPrice.isFinite) {
      final lower = math.log(minPrice);
      final upper = math.log(maxPrice);
      final logSpan = math.max(upper - lower, 1e-5) / visibleFraction;
      final paddedMin = math.exp(lower -
          logSpan * lowerMarginPercent / 100);
      final paddedMax = math.exp(upper +
          logSpan * upperMarginPercent / 100);
      if (paddedMin.isFinite && paddedMax.isFinite &&
          paddedMin > 0 && paddedMax > paddedMin) {
        return ChartPriceScale(
          paddedMin, paddedMax, height,
          logarithmic: true,
          inverted: inverted,
          sourceCandles: candles,
          sourceMinimum: minPrice,
          sourceMaximum: maxPrice,
          sourceVisibleStart: start,
          sourceVisibleEnd: end,
        );
      }
    }
    return ChartPriceScale(
      minPrice - fullSpan * lowerMarginPercent / 100,
      maxPrice + fullSpan * upperMarginPercent / 100, height,
      inverted: inverted,
      referenceMode: safeReferenceMode,
      referencePrice: safeReference,
      sourceCandles: candles,
      sourceMinimum: minPrice,
      sourceMaximum: maxPrice,
      sourceVisibleStart: start,
      sourceVisibleEnd: end,
    );
  }

  double y(double price) {
    double standardY;
    if (!usesLogarithmic) {
      standardY = (maximum - price) / (maximum - minimum) * height;
    } else {
      // A user-created drawing may have a negative level while genuine
      // prices are positive; this cannot enter the visible log plot.
      if (price <= 0) return inverted ? -height * 2 : height * 3;
      standardY = (math.log(maximum) - math.log(price)) /
          (math.log(maximum) - math.log(minimum)) * height;
    }
    return inverted ? height - standardY : standardY;
  }

  double price(double y) {
    final actualY = inverted ? height - y : y;
    if (!usesLogarithmic) {
      return maximum - actualY / height * (maximum - minimum);
    }
    return math.exp(math.log(maximum) -
        actualY / height * (math.log(maximum) - math.log(minimum)));
  }

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
      ChartPriceScale(minimum, maximum, newHeight,
        sourceCandles: sourceCandles,
        sourceMinimum: sourceMinimum,
        sourceMaximum: sourceMaximum,
        sourceVisibleStart: sourceVisibleStart,
        sourceVisibleEnd: sourceVisibleEnd,
        logarithmic: logarithmic,
        inverted: inverted,
        referenceMode: referenceMode,
        referencePrice: referencePrice);

  /// Price-coordinate units per ONE full candle column. For a logarithmic
  /// ruler, units are natural-log price, not fictitious quote prices.
  /// Keeping this constant while [barWidth] changes locks the relative
  /// vertical/horizontal geometry of TradingView-style chart drawings.
  double? pricePerBarRatio(double barWidth) {
    if (!barWidth.isFinite || barWidth <= 0 ||
        !height.isFinite || height <= 0 ||
        !minimum.isFinite || !maximum.isFinite ||
        maximum <= minimum) return null;
    final span = usesLogarithmic
        ? math.log(maximum) - math.log(minimum)
        : maximum - minimum;
    final perBar = span * barWidth / height;
    return perBar.isFinite && perBar > 0 ? perBar : null;
  }

  /// Apply a LOCKED price/bar aspect after time-axis pan, zoom or resize.
  /// The visible source-price center stays fixed for this operation, while
  /// the vertical range changes inversely with actual candle column width.
  /// Source OHLC, historical indices, manual anchor price, and Replay cutoff
  /// are never modified; this is presentation geometry only.
  ChartPriceScale withLockedPricePerBar({
    required double ratio,
    required double barWidth,
  }) {
    if (!ratio.isFinite || ratio <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        !height.isFinite || height <= 0 ||
        !minimum.isFinite || !maximum.isFinite ||
        maximum <= minimum) return this;
    final coordinateSpan = ratio * height / barWidth;
    if (!coordinateSpan.isFinite || coordinateSpan <= 0) return this;
    final logarithmicCoordinates = usesLogarithmic;
    final minCoordinate = logarithmicCoordinates
        ? math.log(minimum) : minimum;
    final maxCoordinate = logarithmicCoordinates
        ? math.log(maximum) : maximum;
    final oldSpan = maxCoordinate - minCoordinate;
    // Most pan frames keep the same bar width and therefore require no
    // replacement scale object. Keep all verified candle metadata cached.
    if ((coordinateSpan - oldSpan).abs() <= oldSpan.abs() * 1e-12) {
      return this;
    }
    final center = minCoordinate + oldSpan / 2;
    final targetMin = center - coordinateSpan / 2;
    final targetMax = center + coordinateSpan / 2;
    final newMin = logarithmicCoordinates
        ? math.exp(targetMin) : targetMin;
    final newMax = logarithmicCoordinates
        ? math.exp(targetMax) : targetMax;
    if (!newMin.isFinite || !newMax.isFinite || newMax <= newMin ||
        (logarithmicCoordinates && newMin <= 0)) return this;
    return ChartPriceScale(newMin, newMax, height,
      logarithmic: logarithmicCoordinates,
      inverted: inverted,
      referenceMode: referenceMode,
      referencePrice: referencePrice,
      sourceCandles: sourceCandles,
      sourceMinimum: sourceMinimum,
      sourceMaximum: sourceMaximum,
      sourceVisibleStart: sourceVisibleStart,
      sourceVisibleEnd: sourceVisibleEnd,
    );
  }

  /// Vertical drag on the RIGHT price scale, independent of time-axis pan.
  /// The price under the user's finger stays at the same y while zooming.
  /// An upward drag magnifies price movement; downward reveals more range.
  /// Pure geometry: no broker OHLC, Replay boundary or drawing is mutated.
  ChartPriceScale dragPriceAxis({
    required double deltaY,
    required double focalY,
  }) {
    final isLog = usesLogarithmic;
    final lower = isLog ? math.log(minimum) : minimum;
    final upper = isLog ? math.log(maximum) : maximum;
    final span = upper - lower;
    if (!deltaY.isFinite || !focalY.isFinite ||
        !height.isFinite || height <= 0 ||
        !minimum.isFinite || !maximum.isFinite ||
        !span.isFinite || span <= 0 || deltaY == 0) {
      return this;
    }
    final zoomFactor = math.exp(
        (-deltaY.clamp(-120.0, 120.0).toDouble()) / 240.0);
    final minSpan = isLog ? 1e-8 :
        math.max(1e-9, (maximum.abs() + minimum.abs()) * 1e-11);
    final nextSpan = (span / zoomFactor).clamp(
        minSpan, isLog ? 100 : 1e15).toDouble();
    if (nextSpan == span) return this;
    final anchorY = focalY.clamp(0.0, height).toDouble();
    final anchorPrice = price(anchorY);
    final coordinate = isLog ? math.log(anchorPrice) : anchorPrice;
    final aboveFraction = inverted
        ? 1 - anchorY / height : anchorY / height;
    final nextUpper = coordinate + aboveFraction * nextSpan;
    final nextLower = coordinate - (1 - aboveFraction) * nextSpan;
    final nextMax = isLog ? math.exp(nextUpper) : nextUpper;
    final nextMin = isLog ? math.exp(nextLower) : nextLower;
    if (!nextMin.isFinite || !nextMax.isFinite ||
        nextMax <= nextMin || (isLog && nextMin <= 0)) {
      return this;
    }
    return ChartPriceScale(nextMin, nextMax, height,
        logarithmic: isLog, inverted: inverted,
        referenceMode: referenceMode, referencePrice: referencePrice);
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
    // A transient Android multi-pointer centroid must never be rounded
    // from NaN/Infinity into a candle index or a fake Replay timestamp.
    if (candleCount <= 0 || !x.isFinite || !plotWidth.isFinite ||
        plotWidth <= 0 || x < 0 || x > plotWidth ||
        !barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite) return null;
    final rawIndex = (x - plotWidth) / barWidth +
        candleCount - scrollBars - .5 + rightMarginBars;
    if (!rawIndex.isFinite) return null;
    final index = rawIndex.round();
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
  }) {
    if (!deltaX.isFinite || !plotWidth.isFinite || plotWidth <= 0 ||
        !barWidth.isFinite || barWidth <= 0 || !scrollBars.isFinite ||
        !rightMarginBars.isFinite || candleCount <= 0) return this;
    return ChartViewport(
      barWidth: barWidth,
      rightMarginBars: rightMarginBars,
      scrollBars: _boundedScroll(
          scrollBars + deltaX / barWidth, plotWidth, candleCount, barWidth),
    );
  }

  /// Keeps the sample under the initial pinch focal point anchored while
  /// zooming. Moving both fingers together also pans the chart naturally.
  ChartViewport pinch({
    required double scale,
    required double initialFocalX,
    required double currentFocalX,
    required double plotWidth,
    required int candleCount,
  }) {
    if (!scale.isFinite || scale <= 0 ||
        !initialFocalX.isFinite || !currentFocalX.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite ||
        candleCount <= 0) return this;
    final width = (barWidth * scale).clamp(minBarWidth, maxBarWidth).toDouble();
    final anchoredScroll = scrollBars +
        (plotWidth - initialFocalX) * (1 / barWidth - 1 / width) +
        (currentFocalX - initialFocalX) / width;
    if (!anchoredScroll.isFinite) return this;
    return ChartViewport(
      barWidth: width,
      rightMarginBars: rightMarginBars,
      scrollBars: _boundedScroll(anchoredScroll, plotWidth, candleCount, width),
    );
  }

  /// Dragging the BOTTOM time ruler adjusts candle width independently
  /// of ordinary one-finger plot panning. Use the EXISTING focal-anchored
  /// pinch transform with identical start/end anchors, so the verified
  /// historical candle under the initial touch stays at its x coordinate.
  ///
  /// Incremental deltas are capped to avoid sudden jumps from Android
  /// pointer handoffs. No new timestamps, broker candles or Replay bars are
  /// synthesized when exposing a wider or narrower source view.
  ChartViewport dragTimeAxis({
    required double deltaX,
    required double anchorX,
    required double plotWidth,
    required int candleCount,
  }) {
    if (!deltaX.isFinite || !anchorX.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0 || candleCount <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite ||
        deltaX == 0) {
      return this;
    }
    final anchor = anchorX.clamp(0.0, plotWidth).toDouble();
    final factor = math.exp(
        deltaX.clamp(-120.0, 120.0).toDouble() / 180.0);
    final next = pinch(
      scale: factor,
      initialFocalX: anchor,
      currentFocalX: anchor,
      plotWidth: plotWidth,
      candleCount: candleCount,
    );
    return next == this ? this : next;
  }

  /// Replay adds and removes confirmed source bars from its *displayed
  /// prefix*, not from the immutable broker history. While inspecting older
  /// bars, their screen x should not drift one column whenever playback
  /// reveals a new bar or manual stepping rewinds. At the live edge
  /// (scrollBars == 0) keep following the newest confirmed candle instead.
  ///
  /// The scroll count changes by exactly the visible-prefix count delta:
  /// chartX(index) depends on (visibleCount - scrollBars - index).
  /// A rewind that removes the user's historical anchor follows the last
  /// still-revealed bar, never blank future or a hidden Replay candle.
  /// This is O(1), including for 100k+ verified source candles.
  ChartViewport afterReplayVisibleCountChange({
    required int previousVisibleCount,
    required int nextVisibleCount,
    required double plotWidth,
  }) {
    if (previousVisibleCount <= 0 || nextVisibleCount <= 0 ||
        previousVisibleCount == nextVisibleCount ||
        !plotWidth.isFinite || plotWidth <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite ||
        scrollBars == 0) return this;

    final delta = nextVisibleCount - previousVisibleCount;
    final proposed = scrollBars + delta;
    if (!proposed.isFinite) return this;
    // The old bar is no longer in the confirmed Replay prefix after a
    // large backwards seek. Anchor to the newest remaining real bar.
    if (scrollBars > 0 && proposed < 0) return jumpToLatest();
    final bounded = _boundedScroll(
        proposed, plotWidth, nextVisibleCount, barWidth);
    if (bounded == scrollBars) return this;
    return ChartViewport(
      barWidth: barWidth,
      scrollBars: bounded,
      rightMarginBars: rightMarginBars,
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
    if (!barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite ||
        scrollBars <= 0 || oldCount < 1 || newCount < 1 ||
        oldIndex < 0 || oldIndex >= oldCount ||
        newIndex < 0 || newIndex >= newCount) {
      return this;
    }
    // chartX depends on (candleCount - scrollBars - index).
    // Preserve that expression at the same bar width and plot width.
    final remapped = scrollBars +
        (newCount - oldCount) - (newIndex - oldIndex);
    if (!remapped.isFinite) return this;
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
        !plotWidth.isFinite || plotWidth <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite) {
      return this;
    }
    final wantedX = plotWidth / 2;
    final proposed = candleCount - index - .5 + rightMarginBars -
        (plotWidth - wantedX) / barWidth;
    // A malformed/restored ultra-small bar width must not produce Infinity
    // and jump Replay to an unrelated historical candle.
    if (!proposed.isFinite) return this;
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
    if (candleCount <= 0 || !plotWidth.isFinite || plotWidth <= 0 ||
        !barWidth.isFinite || barWidth <= 0 ||
        !scrollBars.isFinite || !rightMarginBars.isFinite) return (0, 0);
    final edge = candleCount - scrollBars + rightMarginBars;
    if (!edge.isFinite) return (0, 0);
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
  int _multiPointerCount = 0;

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
      // Flutter may reset its scale and move the centroid abruptly when a
      // third finger joins a two-finger pinch, or when that finger leaves
      // and TWO fingers remain. The old pinch origin belongs to a different
      // pointer group and must never be reused after either transition.
      // On a valid transition the current viewport becomes the new origin
      // immediately, without swallowing an extra touch frame.
      if (_multiPointerCount != pointerCount) {
        _multiPointerCount = pointerCount;
        _pinchOrigin = null;
      }
      // Android can briefly report an invalid focal centroid while the
      // second pointer joins/leaves. Drop that *sample*, not the chart:
      // the first subsequent valid sample rebases pinch at today's viewport.
      if (!focalX.isFinite || !scale.isFinite || scale <= 0) {
        // An invalid sample can arrive *during* a valid Android pinch, not
        // only when the second finger first joins. Flutter's subsequent
        // centroid/scale may be rebased, so abandon the old gesture origin.
        // The next valid two-pointer sample must anchor to the viewport
        // visible now instead of jumping back to the stale origin.
        // Keep the active-pinching flag until the pointer count actually
        // drops. A direct two-to-one transition must still suppress its
        // first synthetic centroid delta, even after an invalid sample.
        _pinchOrigin = null;
        // Even when the *first* two-finger sample is corrupted, remember
        // that a multi-touch session began. Otherwise an immediate lift
        // falls through to one-finger pan and applies its synthetic centroid
        // delta as a real swipe, jumping the chart.
        _pinching = true;
        ignoredPointerTransition = true;
        return viewport;
      }
      if (!_pinching || _pinchOrigin == null) {
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
      _multiPointerCount = 0;
      ignoredPointerTransition = true;
      return viewport;
    }
    if (pointerCount != 1 || !deltaX.isFinite) return viewport;
    final next = viewport.pan(
      deltaX: deltaX, plotWidth: plotWidth, candleCount: candleCount,
    );
    // The finger may keep moving while the chart is clamped at oldest
    // history or the farthest permitted right whitespace. Counting its
    // raw delta as deliberate pan travel could start a pointless fling and
    // schedule animation frames even when NO source candle moved.
    //
    // Measure actual displacement of the viewport in screen pixels.
    // This also counts only the unblocked portion of a drag that hits a
    // historical boundary mid-gesture.
    final movedPixels =
        ((next.scrollBars - viewport.scrollBars) * viewport.barWidth).abs();
    // A clamped floating-point bound can differ from a serialized viewport
    // by only ~3.55e-14 display pixels; this is arithmetic noise, not a
    // gesture or a visible source-candle move. Do not start a fling from it.
    if (movedPixels.isFinite && movedPixels > 1e-9) {
      horizontalTravel += movedPixels;
    }
    return next;
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
