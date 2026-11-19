import 'dart:ui';

import '../data/tradelab_data.dart';
import 'chart_viewport.dart';

typedef ChartWickPaths = ({Path rising, Path falling});

/// Batches the wick strokes of *visible* source candles without changing
/// their timestamps, prices, colors or viewport positions. Each path consists
/// of the exact individual vertical strokes previously passed to drawLine.
///
/// Drawing the two stroke paths before all filled bodies keeps wicks behind
/// candle bodies. Candle columns stay disjoint at the supported bar widths.
class ChartCandleWicks {
  const ChartCandleWicks._();

  static ChartWickPaths visible({
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
    for (var i = start < 0 ? 0 : start; i < end && i < candles.length; i++) {
      final candle = candles[i];
      final x = viewport.chartX(
        index: i, candleCount: candles.length, plotWidth: plotWidth);
      if (!x.isFinite ||
          x < -viewport.barWidth || x > plotWidth + viewport.barWidth) {
        continue;
      }
      final highY = priceY(candle.high);
      final lowY = priceY(candle.low);
      if (!highY.isFinite || !lowY.isFinite) continue;

      final isRising = colorByPreviousClose && i > 0
          ? candle.close >= candles[i - 1].close
          : candle.positive;
      final path = isRising ? rising : falling;
      path.moveTo(x, highY);
      path.lineTo(x, lowY);
    }
    return (rising: rising, falling: falling);
  }
}
