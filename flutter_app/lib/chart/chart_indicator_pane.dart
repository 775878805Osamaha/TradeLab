import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/tradelab_data.dart';
import 'chart_indicator_engine.dart';
import 'chart_indicator_library.dart';
import 'chart_viewport.dart';

/// A genuine independent TradingView-style pane. Values use their own
/// RSI/oscillator/ATR axis, never the source price axis. Its source candle
/// indexes/viewport are shared with the top price chart and Replay prefix.
class ChartIndicatorPane extends StatelessWidget {
  const ChartIndicatorPane({
    required this.candles,
    required this.indicator,
    required this.cache,
    required this.viewport,
    required this.repaint,
    required this.onRemove,
    required this.onScaleStart,
    required this.onScaleUpdate,
    super.key,
  });

  final List<TradeCandle> candles;
  final ChartIndicatorDefinition indicator;
  final ChartIndicatorSeriesCache cache;
  final ChartViewport Function() viewport;
  final Listenable repaint;
  final VoidCallback onRemove;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 106,
    child: Stack(children: [
      Positioned.fill(child: GestureDetector(
        key: Key('chart-indicator-pane-' + indicator.id),
        behavior: HitTestBehavior.opaque,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: ChartIndicatorPanePainter(
              candles: candles,
              indicator: indicator,
              cache: cache,
              viewportProvider: viewport,
              viewportSnapshot: viewport(),
              repaint: repaint,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      )),
      Positioned(left: 8, top: 4, child: Row(children: [
        Text(indicator.title,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(width: 4),
        SizedBox(height: 28, width: 28,
          child: IconButton(
            key: Key('chart-indicator-remove-' + indicator.id),
            tooltip: 'إزالة المؤشر',
            padding: EdgeInsets.zero,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ),
      ])),
    ]),
  );
}

/// Independent panel painter. All y-axis labels refer to indicator values,
/// not to broker price quotes; x positions are identical to candle x.
class ChartIndicatorPanePainter extends CustomPainter {
  ChartIndicatorPanePainter({
    required this.candles,
    required this.indicator,
    required this.cache,
    required this.viewportProvider,
    required this.viewportSnapshot,
    required this.dark,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<TradeCandle> candles;
  final ChartIndicatorDefinition indicator;
  final ChartIndicatorSeriesCache cache;
  final ChartViewport Function() viewportProvider;
  final ChartViewport viewportSnapshot;
  final bool dark;

  static const _lineColors = <Color>[
    Color(0xFF2962FF), Color(0xFFFF9800), Color(0xFF009688),
  ];

  void _text(Canvas canvas, String label, Offset where, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: label,
        style: TextStyle(color: color, fontSize: 10)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 61);
    tp.paint(canvas, where);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = dark ? const Color(0xFF0B1724) : const Color(0xFFFFFFFF);
    final grid = dark ? const Color(0xFF334455) : const Color(0xFFE8EAF0);
    final textColor = dark
        ? const Color(0xFFBEC8D7) : const Color(0xFF6D7280);
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    canvas.drawLine(Offset.zero, Offset(size.width, 0),
        Paint()..color = grid..strokeWidth = 1);

    final plotWidth = size.width - 61;
    if (plotWidth < 30 || size.height < 40 || candles.isEmpty) return;
    final v = viewportProvider();
    final (start, end) = v.visibleIndices(
        plotWidth: plotWidth, candleCount: candles.length);
    if (start >= end) return;
    final output = cache.get(candles, indicator);
    if (output.plots.isEmpty) return;

    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    if (indicator.kind == ChartIndicatorKind.rsi) {
      minimum = 0;
      maximum = 100;
    } else {
      for (final series in output.plots) {
        for (var i = start; i < end; i++) {
          final value = series.values[i];
          if (value == null || !value.isFinite) continue;
          minimum = math.min(minimum, value);
          maximum = math.max(maximum, value);
        }
      }
      if (!minimum.isFinite || !maximum.isFinite) return;
      if (indicator.kind == ChartIndicatorKind.macd) {
        final extreme = math.max(minimum.abs(), maximum.abs());
        minimum = -math.max(1e-10, extreme * 1.12);
        maximum = math.max(1e-10, extreme * 1.12);
      } else {
        minimum = 0;
        maximum = math.max(1e-10, maximum * 1.12);
      }
    }

    final top = 21.0;
    final bottom = size.height - 10.0;
    if (bottom <= top) return;
    final height = bottom - top;
    double y(double value) =>
        top + height * (maximum - value) / (maximum - minimum);
    void guide(double value, bool bold) {
      final yy = y(value);
      if (!yy.isFinite || yy < 0 || yy > size.height) return;
      canvas.drawLine(Offset(0, yy), Offset(plotWidth, yy),
          Paint()..color = grid..strokeWidth = bold ? 1 : .65);
      _text(canvas, value.toStringAsFixed(
          indicator.kind == ChartIndicatorKind.rsi ? 0 : 2),
          Offset(plotWidth + 4, yy - 6), textColor);
    }

    if (indicator.kind == ChartIndicatorKind.rsi) {
      guide(70, false);
      guide(50, true);
      guide(30, false);
    } else if (indicator.kind == ChartIndicatorKind.macd) {
      guide(0, true);
      guide(maximum, false);
      guide(minimum, false);
    } else {
      guide(0, true);
      guide(maximum, false);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, top, plotWidth, height));
    for (var j = 0; j < output.plots.length; j++) {
      final series = output.plots[j];
      final color = _lineColors[j % _lineColors.length];
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      if (series.histogram) {
        final zeroY = y(0);
        for (var i = start; i < end; i++) {
          final value = series.values[i];
          if (value == null || !value.isFinite) continue;
          final x = v.chartX(
            index: i, candleCount: candles.length, plotWidth: plotWidth);
          if (x < -v.barWidth || x > plotWidth + v.barWidth) continue;
          canvas.drawLine(Offset(x, zeroY), Offset(x, y(value)), Paint()
            ..color = value >= 0
                ? const Color(0xFF26A69A) : const Color(0xFFEF5350)
            ..strokeWidth = math.max(1.0, v.barWidth * .6));
        }
      } else {
        final path = Path();
        var started = false;
        for (var i = start; i < end; i++) {
          final value = series.values[i];
          if (value == null || !value.isFinite) {
            started = false;
            continue;
          }
          final x = v.chartX(
            index: i, candleCount: candles.length, plotWidth: plotWidth);
          if (!started) {
            path.moveTo(x, y(value));
            started = true;
          } else {
            path.lineTo(x, y(value));
          }
        }
        canvas.drawPath(path, stroke);
      }
    }
    canvas.restore();
    canvas.drawLine(Offset(plotWidth, 0),
        Offset(plotWidth, size.height),
        Paint()..color = grid..strokeWidth = .75);
  }

  @override
  bool shouldRepaint(covariant ChartIndicatorPanePainter old) =>
      !identical(candles, old.candles) ||
      indicator != old.indicator ||
      viewportSnapshot != old.viewportSnapshot ||
      dark != old.dark || cache != old.cache;
}
