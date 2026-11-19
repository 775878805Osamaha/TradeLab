import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_candle_bodies.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// Raster comparison of the old per-candle drawRect pipeline and the new
/// per-color drawPath batching; requires only Flutter's test rasterizer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final candles = List<TradeCandle>.generate(140, (i) {
    final open = 100.0 + (i % 7) * 2;
    final close = i % 9 == 0 ? open
        : open + (i.isEven ? 2.0 : -3.0);
    return TradeCandle(open, math.max(open, close) + 4,
        math.min(open, close) - 3, close);
  }, growable: false);

  Future<Uint8List> render({
    required bool batched,
    required double candleWidth,
    required bool bodies,
    required bool borders,
    required bool colorByPreviousClose,
  }) async {
    const width = 320, height = 220, plotWidth = 259.0;
    const chartHeight = 200.0;
    final viewport = ChartViewport(barWidth: candleWidth);
    final (start, end) = viewport.visibleIndices(
      plotWidth: plotWidth, candleCount: candles.length);
    double y(double price) => (122.0 - price) * 4;

    final positiveBody = ui.Paint()..color = const ui.Color(0xFF089981);
    final negativeBody = ui.Paint()..color = const ui.Color(0xFFF23645);
    final positiveBorder = ui.Paint()
      ..color = const ui.Color(0xFF16806B)
      ..strokeWidth = 1.0
      ..style = ui.PaintingStyle.stroke;
    final negativeBorder = ui.Paint()
      ..color = const ui.Color(0xFFD5293B)
      ..strokeWidth = 1.0
      ..style = ui.PaintingStyle.stroke;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, const ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.drawColor(const ui.Color(0xFF101C23), ui.BlendMode.src);
    canvas.save();
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, plotWidth, chartHeight));

    if (batched) {
      final paths = ChartCandleBodies.visible(
        candles: candles, viewport: viewport, start: start, end: end,
        plotWidth: plotWidth, priceY: y,
        colorByPreviousClose: colorByPreviousClose,
      );
      if (bodies) {
        canvas.drawPath(paths.rising, positiveBody);
        canvas.drawPath(paths.falling, negativeBody);
      }
      if (borders) {
        canvas.drawPath(paths.rising, positiveBorder);
        canvas.drawPath(paths.falling, negativeBorder);
      }
    } else {
      // Exact previous _CandleChartPainter body loop, including its ordering.
      for (var i = start; i < end; i++) {
        final candle = candles[i];
        final rising = colorByPreviousClose && i > 0
            ? candle.close >= candles[i - 1].close
            : candle.positive;
        final centerX = viewport.chartX(
          index: i, candleCount: candles.length, plotWidth: plotWidth);
        if (centerX < -viewport.barWidth ||
            centerX > plotWidth + viewport.barWidth) continue;
        final openY = y(candle.open);
        final closeY = y(candle.close);
        final rect = ui.Rect.fromLTRB(
          centerX - viewport.barWidth * .34,
          math.min(openY, closeY),
          centerX + viewport.barWidth * .34,
          math.max(openY + 1, closeY + 1),
        );
        if (bodies) {
          canvas.drawRect(rect, rising ? positiveBody : negativeBody);
        }
        if (borders) {
          canvas.drawRect(rect, rising ? positiveBorder : negativeBorder);
        }
      }
    }

    canvas.restore();
    final picture = recorder.endRecording();
    final frame = await picture.toImage(width, height);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.dispose();
    picture.dispose();
    if (bytes == null) {
      throw StateError('Could not rasterize body-paint regression fixture');
    }
    return Uint8List.fromList(bytes.buffer.asUint8List(
      bytes.offsetInBytes, bytes.lengthInBytes));
  }

  for (final width in <double>[3, 10, 60]) {
    for (final previousClose in <bool>[false, true]) {
      for (final visibility in <(bool, bool)>[
        (true, false), (false, true), (true, true),
      ]) {
        final (body, border) = visibility;
        test('batched bodies preserve pixels at ${width}dp '
            '(previousClose=$previousClose, body=$body, border=$border)',
            () async {
          final before = await render(
            batched: false, candleWidth: width,
            bodies: body, borders: border,
            colorByPreviousClose: previousClose,
          );
          final after = await render(
            batched: true, candleWidth: width,
            bodies: body, borders: border,
            colorByPreviousClose: previousClose,
          );
          expect(after.length, before.length);
          var differingPixels = 0;
          for (var index = 0; index < before.length; index += 4) {
            if (before[index] != after[index] ||
                before[index + 1] != after[index + 1] ||
                before[index + 2] != after[index + 2] ||
                before[index + 3] != after[index + 3]) {
              differingPixels++;
            }
          }
          expect(differingPixels, 0,
            reason: 'New per-color Path output must match the old drawRect '
                'raster at the selected density and body/border settings.');
        });
      }
    }
  }
}
