import 'dart:math' as math;
import 'dart:ui';

import '../data/tradelab_data.dart';
import 'chart_viewport.dart';

typedef ChartBodyPaths = ({Path rising, Path falling});

/// Visible OHLC body geometry for both fill and outline painting.
///
/// The paths reuse the exact per-candle Rect.fromLTRB bounds from the chart
/// painter. Color grouping changes canvas call count, not the underlying
/// broker OHLC, viewport X coordinates, or candle width. Replay callers
/// pass the already-revealed candle prefix, never the full future archive.
class ChartCandleBodies {
  const ChartCandleBodies._();

  static ChartBodyPaths visible({
    required List<TradeCandle> candles,
    required ChartViewport viewport,
    required int start,
    required int end,
    required double plotWidth,
    required double Function(double price) priceY,
    required bool colorByPreviousClose,
  }) {
    final rising = Path();
    final falling = Path();
    if (!plotWidth.isFinite || plotWidth <= 0 ||
        !viewport.barWidth.isFinite || viewport.barWidth <= 0) {
      return (rising: rising, falling: falling);
    }

    for (var i = math.max(0, start); i < end && i < candles.length; i++) {
      final candle = candles[i];
      final centerX = viewport.chartX(
        index: i, candleCount: candles.length, plotWidth: plotWidth);
      if (!centerX.isFinite ||
          centerX < -viewport.barWidth ||
          centerX > plotWidth + viewport.barWidth) continue;
      final openY = priceY(candle.open);
      final closeY = priceY(candle.close);
      if (!openY.isFinite || !closeY.isFinite) continue;

      // Exact previous per-body painter bounds: preserve even a 1px doji.
      final rect = Rect.fromLTRB(
        centerX - viewport.barWidth * .34, math.min(openY, closeY),
        centerX + viewport.barWidth * .34,
        math.max(openY + 1, closeY + 1),
      );
      final bullish = colorByPreviousClose && i > 0
          ? candle.close >= candles[i - 1].close
          : candle.positive;
      (bullish ? rising : falling).addRect(rect);
    }
    return (rising: rising, falling: falling);
  }
}
