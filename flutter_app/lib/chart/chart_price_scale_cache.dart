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
/// independent price extrema. The value-equal ChartViewport key also includes
/// scroll offset, zoom and right-margin preference, ensuring every source
/// candle location used by the crosshair/axis/drawings stays identical.
class ChartPriceScaleCache {
  List<TradeCandle>? _candles;
  ChartViewport? _viewport;
  int? _count;
  double? _plotWidth;
  double? _plotHeight;
  bool? _logarithmic;
  int? _topMargin;
  int? _bottomMargin;
  ChartPriceScale? _scale;

  ChartPriceScale resolve({
    required List<TradeCandle> candles,
    required ChartViewport viewport,
    required double plotWidth,
    required double plotHeight,
    bool logarithmic = false,
    required int topMarginPercent,
    required int bottomMarginPercent,
  }) {
    final cached = _scale;
    if (cached != null &&
        identical(_candles, candles) &&
        _count == candles.length &&
        _viewport == viewport &&
        _plotWidth == plotWidth &&
        _plotHeight == plotHeight &&
        _logarithmic == logarithmic &&
        _topMargin == topMarginPercent &&
        _bottomMargin == bottomMarginPercent) {
      return cached;
    }

    final computed = ChartPriceScale.visible(
      candles, viewport, plotWidth, plotHeight,
      topMarginPercent: topMarginPercent,
      bottomMarginPercent: bottomMarginPercent,
      logarithmic: logarithmic,
    );
    _candles = candles;
    _viewport = viewport;
    _count = candles.length;
    _plotWidth = plotWidth;
    _plotHeight = plotHeight;
    _logarithmic = logarithmic;
    _topMargin = topMarginPercent;
    _bottomMargin = bottomMarginPercent;
    _scale = computed;
    return computed;
  }

  void clear() {
    _candles = null;
    _viewport = null;
    _count = null;
    _plotWidth = null;
    _plotHeight = null;
    _logarithmic = null;
    _topMargin = null;
    _bottomMargin = null;
    _scale = null;
  }
}
