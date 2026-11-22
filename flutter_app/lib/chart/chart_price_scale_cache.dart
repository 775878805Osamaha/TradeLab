import '../data/tradelab_data.dart';
import 'chart_viewport.dart';

/// One-entry automatic price scale cache shared by the candle painter,
/// on-chart drawing overlays and touch hit-tests.
///
/// Chart history snapshots are published as new lists when verified broker
/// OHLC or the Replay prefix changes. A repaint driven only by a viewport
/// notifier can request the SAME scale several times per frame. Recomputing
/// its visible high/low for every overlay copies no market data, but still
/// scans the visible candle interval and allocates geometry repeatedly.
///
/// Keep exactly one value: no growing LRU and no cached historical snapshots.
/// Identity is intentional: two source lists with equal candle counts need
/// independent price extrema. Scale high/low and the relative price baseline
/// depend on the actual *visible candle indices*, not fractional pan offsets.
/// Reuse the same source scale while touch pan changes only pixels, but renew
/// the scale whenever an index enters/exits, zoom changes or any display
/// settings or verified source snapshot changes.
class ChartPriceScaleCache {
  List<TradeCandle>? _candles;
  double? _barWidth;
  double? _rightMarginBars;
  int? _visibleStart;
  int? _visibleEnd;
  int? _count;
  double? _plotWidth;
  double? _plotHeight;
  bool? _logarithmic;
  bool? _inverted;
  ChartPriceReferenceMode? _referenceMode;
  int? _topMargin;
  int? _bottomMargin;
  ChartPriceScale? _scale;

  ChartPriceScale resolve({
    required List<TradeCandle> candles,
    required ChartViewport viewport,
    required double plotWidth,
    required double plotHeight,
    bool logarithmic = false,
    bool inverted = false,
    ChartPriceReferenceMode referenceMode = ChartPriceReferenceMode.price,
    required int topMarginPercent,
    required int bottomMarginPercent,
  }) {
    // This O(1) interval check avoids scanning every visible OHLC on each
    // sub-candle pixel pan. The painter and source scale use the very same
    // ChartViewport.visibleIndices; no historical future can enter the cache.
    final (visibleStart, visibleEnd) = viewport.visibleIndices(
      plotWidth: plotWidth, candleCount: candles.length);
    final cached = _scale;
    // Keep the last AUTO price interval when the user deliberately pans
    // past all loaded candles. The viewport is blank, not the market:
    // resetting its ruler to a synthetic 0..1 or jumping to unrelated
    // history breaks the TradingView-style anchored axis.
    //
    // Safe only for the SAME immutable broker/Replay-prefix list and all
    // same scale settings. A newly published candle list or revealed Replay
    // prefix cannot inherit an earlier session's future extrema. If there
    // is no cached source window, ChartPriceScale.visible derives a bounded
    // fallback from its nearest verified edge, never fake prices.
    if (visibleStart >= visibleEnd && cached != null &&
        identical(_candles, candles) &&
        _count == candles.length &&
        candles.isNotEmpty &&
        _logarithmic == logarithmic &&
        _inverted == inverted &&
        _referenceMode == referenceMode &&
        _topMargin == topMarginPercent &&
        _bottomMargin == bottomMarginPercent) {
      return cached.height == plotHeight
          ? cached : cached.withHeight(plotHeight);
    }
    if (cached != null &&
        identical(_candles, candles) &&
        _count == candles.length &&
        _barWidth == viewport.barWidth &&
        _rightMarginBars == viewport.rightMarginBars &&
        _visibleStart == visibleStart &&
        _visibleEnd == visibleEnd &&
        _plotWidth == plotWidth &&
        _plotHeight == plotHeight &&
        _logarithmic == logarithmic &&
        _inverted == inverted &&
        _referenceMode == referenceMode &&
        _topMargin == topMarginPercent &&
        _bottomMargin == bottomMarginPercent) {
      return cached;
    }

    final computed = ChartPriceScale.visible(
      candles, viewport, plotWidth, plotHeight,
      topMarginPercent: topMarginPercent,
      bottomMarginPercent: bottomMarginPercent,
      logarithmic: logarithmic,
      inverted: inverted,
      referenceMode: referenceMode,
    );
    _candles = candles;
    _barWidth = viewport.barWidth;
    _rightMarginBars = viewport.rightMarginBars;
    _visibleStart = visibleStart;
    _visibleEnd = visibleEnd;
    _count = candles.length;
    _plotWidth = plotWidth;
    _plotHeight = plotHeight;
    _logarithmic = logarithmic;
    _inverted = inverted;
    _referenceMode = referenceMode;
    _topMargin = topMarginPercent;
    _bottomMargin = bottomMarginPercent;
    _scale = computed;
    return computed;
  }

  void clear() {
    _candles = null;
    _barWidth = null;
    _rightMarginBars = null;
    _visibleStart = null;
    _visibleEnd = null;
    _count = null;
    _plotWidth = null;
    _plotHeight = null;
    _logarithmic = null;
    _inverted = null;
    _referenceMode = null;
    _topMargin = null;
    _bottomMargin = null;
    _scale = null;
  }
}
