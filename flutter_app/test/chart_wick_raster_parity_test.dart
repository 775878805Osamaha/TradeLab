import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_candle_wicks.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const imageWidth = 360;
  const imageHeight = 220;
  const plotWidth = 259.0;
  const chartHeight = 200.0;

  final candles = List<TradeCandle>.generate(140, (i) {
    final open = 100.0 + (i % 7) * 2;
    final close = i % 9 == 0 ? open : open + (i.isEven ? 2.0 : -3.0);
    return TradeCandle(open, math.max(open, close) + 4,
      math.min(open, close) - 3, close);
  }, growable: false);

  Future<Uint8List> raster({
    required bool batched,
    required double barWidth,
    required bool colorByPreviousClose,
  }) async {
    final viewport = ChartViewport(barWidth: barWidth);
    final (start, end) = viewport.visibleIndices(
      plotWidth: plotWidth, candleCount: candles.length);
    double y(double price) => (125 - price) * 4;
    final positiveWick = ui.Paint()
      ..color = const ui.Color(0xFF089981)
      ..strokeWidth = 1.0
      ..style = ui.PaintingStyle.stroke;
    final negativeWick = ui.Paint()
      ..color = const ui.Color(0xFFF23645)
      ..strokeWidth = 1.0
      ..style = ui.PaintingStyle.stroke;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF101C23), ui.BlendMode.src);
    canvas.save();
    canvas.clipRect(const ui.Rect.fromLTWH(
      0, 0, plotWidth, chartHeight,
    ));
    if (batched) {
      final paths = ChartCandleWicks.visible(
        candles: candles, viewport: viewport, start: start, end: end,
        plotWidth: plotWidth, priceY: y,
        colorByPreviousClose: colorByPreviousClose,
      );
      canvas.drawPath(paths.rising, positiveWick);
      canvas.drawPath(paths.falling, negativeWick);
    } else {
      // Legacy implementation before PR #537, with identical source candles.
      for (var i = start; i < end; i++) {
        final candle = candles[i];
        final bullish = colorByPreviousClose && i > 0
            ? candle.close >= candles[i - 1].close
            : candle.positive;
        final x = viewport.chartX(
          index: i, candleCount: candles.length, plotWidth: plotWidth);
        if (x < -viewport.barWidth || x > plotWidth + viewport.barWidth) {
          continue;
        }
        canvas.drawLine(ui.Offset(x, y(candle.high)),
          ui.Offset(x, y(candle.low)),
          bullish ? positiveWick : negativeWick);
      }
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('Missing raster image pixels');
    return Uint8List.fromList(data.buffer.asUint8List(
      data.offsetInBytes, data.lengthInBytes,
    ));
  }

  for (final barWidth in <double>[3, 10, 60]) {
    for (final previousClose in <bool>[false, true]) {
      test('wick stroke batching matches legacy raster at '
          '${barWidth}dp, previousClose=$previousClose', () async {
        final before = await raster(
          batched: false, barWidth: barWidth,
          colorByPreviousClose: previousClose);
        final after = await raster(
          batched: true, barWidth: barWidth,
          colorByPreviousClose: previousClose);
        expect(after.length, before.length);
        var differingPixels = 0;
        for (var i = 0; i < before.length; i += 4) {
          if (before[i] != after[i] ||
              before[i + 1] != after[i + 1] ||
              before[i + 2] != after[i + 2] ||
              before[i + 3] != after[i + 3]) {
            differingPixels++;
          }
        }
        expect(differingPixels, 0,
          reason: 'Path batching must not alter wick antialiasing or color.');
      });
    }
  }
}
