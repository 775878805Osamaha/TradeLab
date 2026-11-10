import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_viewport.dart';
import '../theme/tradelab_theme.dart';

/// A price/time annotation, not an order or a synthetic market range.
/// Both axes are anchored to actual candle indices and prices.
class ChartPriceRectangle {
  const ChartPriceRectangle({
    required this.startIndex,
    required this.endIndex,
    required this.upper,
    required this.lower,
    this.borderColorValue = 0xFFD5A63C,
    this.fillColorValue = 0xFF5BAD6F,
    this.strokeWidth = 1,
  }) : assert(startIndex >= 0),
       assert(endIndex > startIndex),
       assert(upper > lower && lower > 0);

  final int startIndex;
  final int endIndex;
  final double upper;
  final double lower;
  final int borderColorValue;
  final int fillColorValue;
  final double strokeWidth;

  ChartPriceRectangle shifted(int earlierCount) => reanchored(
        startIndex + earlierCount, endIndex + earlierCount);

  ChartPriceRectangle reanchored(int first, int last) => ChartPriceRectangle(
        startIndex: math.min(first, last), endIndex: math.max(first, last),
        upper: upper, lower: lower, borderColorValue: borderColorValue,
        fillColorValue: fillColorValue, strokeWidth: strokeWidth);

  ChartPriceRectangle? edited({int? startIndex, int? endIndex,
      double? upper, double? lower, int? borderColorValue,
      int? fillColorValue, double? strokeWidth}) {
    final first = startIndex ?? this.startIndex;
    final last = endIndex ?? this.endIndex;
    final high = upper ?? this.upper;
    final low = lower ?? this.lower;
    final width = strokeWidth ?? this.strokeWidth;
    if (first < 0 || last <= first || !high.isFinite || !low.isFinite ||
        !(high > low && low > 0) || !width.isFinite || width < .5 || width > 8) {
      return null;
    }
    return ChartPriceRectangle(startIndex: first, endIndex: last,
      upper: high, lower: low,
      borderColorValue: borderColorValue ?? this.borderColorValue,
      fillColorValue: fillColorValue ?? this.fillColorValue,
      strokeWidth: width);
  }

  ChartPriceRectangle? moved(int barDelta, double priceDelta) => edited(
      startIndex: startIndex + barDelta,
      endIndex: endIndex + barDelta,
      upper: upper + priceDelta,
      lower: lower + priceDelta);

  ChartPriceRectangle? withHandle(PriceRectangleHandle handle,
      int bar, double price) => switch (handle) {
    PriceRectangleHandle.topLeft => edited(startIndex: bar, upper: price),
    PriceRectangleHandle.topCenter => edited(upper: price),
    PriceRectangleHandle.topRight => edited(endIndex: bar, upper: price),
    PriceRectangleHandle.middleLeft => edited(startIndex: bar),
    PriceRectangleHandle.middleRight => edited(endIndex: bar),
    PriceRectangleHandle.bottomLeft => edited(startIndex: bar, lower: price),
    PriceRectangleHandle.bottomCenter => edited(lower: price),
    PriceRectangleHandle.bottomRight => edited(endIndex: bar, lower: price),
  };

  bool visibleAt(int count) => startIndex < count && endIndex < count;
}

/// Screenshot 1002906334 has six circular edge handles and two rounded
/// square centre handles. Their visual radii and hit radii are separate.
enum PriceRectangleHandle {
  topLeft, topCenter, topRight,
  middleLeft, middleRight,
  bottomLeft, bottomCenter, bottomRight,
}

abstract final class PriceRectangleGeometry {
  static Rect rect(ChartPriceRectangle drawing, ChartViewport viewport,
      ChartPriceScale scale, int count, double plotWidth) => Rect.fromLTRB(
        viewport.chartX(index: drawing.startIndex,
            candleCount: count, plotWidth: plotWidth),
        scale.y(drawing.upper),
        viewport.chartX(index: drawing.endIndex,
            candleCount: count, plotWidth: plotWidth),
        scale.y(drawing.lower),
      );

  static Map<PriceRectangleHandle, Offset> handles(Rect area) {
    final center = area.center.dx;
    return {
      PriceRectangleHandle.topLeft: area.topLeft,
      PriceRectangleHandle.topCenter: Offset(center, area.top),
      PriceRectangleHandle.topRight: area.topRight,
      PriceRectangleHandle.middleLeft: Offset(area.left, area.center.dy),
      PriceRectangleHandle.middleRight: Offset(area.right, area.center.dy),
      PriceRectangleHandle.bottomLeft: area.bottomLeft,
      PriceRectangleHandle.bottomCenter: Offset(center, area.bottom),
      PriceRectangleHandle.bottomRight: area.bottomRight,
    };
  }

  /// The nullable handle represents a drag on the interior of the rectangle.
  static (int, PriceRectangleHandle?)? hitTest(Offset point,
      List<ChartPriceRectangle> drawings, ChartViewport viewport,
      ChartPriceScale scale, int count, double plotWidth) {
    for (var i = drawings.length - 1; i >= 0; i--) {
      final drawing = drawings[i];
      if (!drawing.visibleAt(count)) continue;
      final area = rect(drawing, viewport, scale, count, plotWidth);
      for (final entry in handles(area).entries) {
        if ((entry.value - point).distance <= 23) return (i, entry.key);
      }
      if (area.inflate(4).contains(point)) return (i, null);
    }
    return null;
  }
}

/// Rendered independently from candle bodies so handle drags need not repaint
/// the chart's potentially large historical candle layer.
class ChartPriceRectanglePainter extends CustomPainter {
  ChartPriceRectanglePainter({required this.drawings,
    required this.selectedIndex, required this.viewport, required this.scale,
    required this.candleCount, required this.plotWidth, required this.dark,
    this.timestamps = const []});

  final List<ChartPriceRectangle> drawings;
  final int? selectedIndex;
  final ChartViewport viewport;
  final ChartPriceScale scale;
  final int candleCount;
  final double plotWidth;
  final bool dark;
  final List<int> timestamps;

  @override
  void paint(Canvas canvas, Size size) {
    if (candleCount == 0 || size.height < 30 || plotWidth <= 0) return;
    final chartHeight = scale.height;
    for (var i = 0; i < drawings.length; i++) {
      final drawing = drawings[i];
      if (!drawing.visibleAt(candleCount)) continue;
      final area = PriceRectangleGeometry.rect(
          drawing, viewport, scale, candleCount, plotWidth);
      if (area.right < 0 || area.left > plotWidth) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, plotWidth, chartHeight));
      canvas.drawRect(area, Paint()
        ..color = Color(drawing.fillColorValue).withValues(alpha: .36));
      final edge = Paint()
        ..color = Color(drawing.borderColorValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = drawing.strokeWidth;
      canvas.drawRect(area, edge);
      if (selectedIndex == i) {
        final positions = PriceRectangleGeometry.handles(area);
        for (final handle in PriceRectangleHandle.values) {
          final center = positions[handle]!;
          final square = handle == PriceRectangleHandle.topCenter ||
              handle == PriceRectangleHandle.bottomCenter;
          if (square) {
            final rounded = RRect.fromRectAndRadius(
              Rect.fromCenter(center: center, width: 22, height: 22),
              const Radius.circular(5));
            canvas.drawRRect(rounded, Paint()..color = Colors.white);
            canvas.drawRRect(rounded, Paint()..color = TradeColors.rectangleHandle
              ..style = PaintingStyle.stroke..strokeWidth = 3.4);
          } else {
            canvas.drawCircle(center, 11.5, Paint()..color = Colors.white);
            canvas.drawCircle(center, 11.5, Paint()
              ..color = TradeColors.rectangleHandle
              ..style = PaintingStyle.stroke..strokeWidth = 3.2);
          }
        }
      }
      canvas.restore();
      if (selectedIndex == i) {
        _priceTag(canvas, drawing.upper, scale.y(drawing.upper), size);
        _priceTag(canvas, drawing.lower, scale.y(drawing.lower), size);
        if (timestamps.length >= candleCount) {
          _timeTag(canvas, drawing.endIndex, area.center.dx, size);
        }
      }
    }
  }

  void _timeTag(Canvas canvas, int index, double atX, Size size) {
    if (index < 0 || index >= timestamps.length) return;
    final time = DateTime.fromMillisecondsSinceEpoch(
        timestamps[index], isUtc: true);
    final label = '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')} UTC';
    final painter = TextPainter(text: TextSpan(text: label,
        style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        maxLines: 1, textDirection: TextDirection.ltr)..layout();
    final left = (atX - painter.width / 2 - 8).clamp(0.0,
        math.max(0.0, plotWidth - painter.width - 16)).toDouble();
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(left, scale.height + 1,
          painter.width + 16, math.min(21, size.height - scale.height)),
      const Radius.circular(2)), Paint()..color = TradeColors.rectangleAxisTag);
    painter.paint(canvas, Offset(left + 8, scale.height + 3));
  }

  void _priceTag(Canvas canvas, double value, double y, Size size) {
    if (y < 0 || y > scale.height) return;
    final span = scale.maximum - scale.minimum;
    final decimals = span < .05 ? 5 : span < 1 ? 4 : span < 20 ? 2 : 1;
    final label = _price(value, decimals);
    const height = 19.0;
    final top = (y - height / 2)
        .clamp(0.0, math.max(0, scale.height - height)).toDouble();
    canvas.drawRect(Rect.fromLTWH(plotWidth, top,
        math.max(0, size.width - plotWidth), height),
      Paint()..color = TradeColors.rectangleAxisTag);
    final painter = TextPainter(text: TextSpan(text: label,
      style: const TextStyle(fontSize: 10.5, color: Colors.white,
        fontWeight: FontWeight.w500)),
      textDirection: TextDirection.ltr, maxLines: 1)..layout();
    painter.paint(canvas, Offset(plotWidth + 3, top + 2));
  }

  static String _price(double number, int decimals) {
    final parts = number.toStringAsFixed(decimals).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return decimals == 0 ? integer : '$integer.${parts.last}';
  }

  @override
  bool shouldRepaint(covariant ChartPriceRectanglePainter old) =>
      old.drawings != drawings || old.selectedIndex != selectedIndex ||
      old.viewport != viewport || old.scale.minimum != scale.minimum ||
      old.scale.maximum != scale.maximum || old.scale.height != scale.height ||
      old.candleCount != candleCount || old.plotWidth != plotWidth ||
      old.dark != dark || old.timestamps != timestamps;
}
