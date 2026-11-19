import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_viewport.dart';
import 'chart_symbol_settings.dart';
import 'chart_text_layout_cache.dart';
import '../theme/tradelab_theme.dart';

/// A selected rectangle's time tag must agree with the SAME display zone
/// chosen for the chart candles. Source UTC timestamps remain untouched.
abstract final class ChartRectangleTimeLabel {
  static String fromSource(int timestampUtcMs, ChartTimeZone zone) {
    final time = zone.displayDate(timestampUtcMs);
    String two(int n) => n.toString().padLeft(2, '0');
    final zoneText = switch (zone) {
      ChartTimeZone.utc => 'UTC',
      ChartTimeZone.device => 'LOCAL',
      ChartTimeZone.newYork => 'NY UTC${ChartTimeZone.newYorkOffset(
          DateTime.fromMillisecondsSinceEpoch(
              timestampUtcMs, isUtc: true)).inHours}',
    };
    return '${two(time.day)}/${two(time.month)} '
        '${two(time.hour)}:${two(time.minute)} $zoneText';
  }
}

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
  /// Exact clipping predicate for the independent rectangle painter.
  /// A selected circular handle may extend 11.5 px past the vertical
  /// plot edge; do not prematurely hide that visible section.
  static bool visibleInPlot(Rect bounds, double width, double height,
      {bool selected = false}) {
    if (!width.isFinite || !height.isFinite ||
        width <= 0 || height <= 0 ||
        !bounds.left.isFinite || !bounds.right.isFinite ||
        !bounds.top.isFinite || !bounds.bottom.isFinite) return false;
    final bleed = selected ? 11.5 : 0.0;
    return bounds.right >= 0 && bounds.left <= width &&
        bounds.bottom >= -bleed && bounds.top <= height + bleed;
  }

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
    // A drawing tool must never steal touch events from the right price
    // ruler, bottom time axis or an invalid Flutter gesture coordinate.
    if (!point.dx.isFinite || !point.dy.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0 ||
        !scale.height.isFinite || scale.height <= 0 ||
        point.dx < 0 || point.dx >= plotWidth ||
        point.dy < 0 || point.dy >= scale.height) return null;
    for (var i = drawings.length - 1; i >= 0; i--) {
      final drawing = drawings[i];
      if (!drawing.visibleAt(count)) continue;
      final area = rect(drawing, viewport, scale, count, plotWidth);
      // Most historical drawings are beyond the visible candle viewport.
      // Reject their bounds before creating all eight handle positions.
      // The painter clips rectangles at the plot's left/right edges.
      if (area.right < 0 || area.left > plotWidth ||
          area.bottom < -11.5 ||
          area.top > scale.height + 11.5 ||
          !area.inflate(23).contains(point)) continue;
      for (final entry in handles(area).entries) {
        final center = entry.value;
        // Hit radius is intentionally 23px for accessibility, but a handle
        // wholly clipped from the plot (visual radius 11.5px) may not be
        // selected invisibly after panning or extreme 3px-bar zoom.
        if (center.dx < -11.5 || center.dx > plotWidth + 11.5 ||
            center.dy < -11.5 || center.dy > scale.height + 11.5) {
          continue;
        }
        if ((center - point).distance <= 23) return (i, entry.key);
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
    this.timestamps = const [], this.textCache,
    this.timeZone = ChartTimeZone.utc,
    List<ChartPriceRectangle> Function()? drawingsProvider,
    ChartViewport Function()? viewportProvider,
    ChartPriceScale Function()? scaleProvider,
    Listenable? repaint,
  }) : _drawingsProvider = drawingsProvider,
       _viewportProvider = viewportProvider,
       _scaleProvider = scaleProvider,
       super(repaint: repaint);

  final List<ChartPriceRectangle> drawings;
  // A paint-only drag updates existing source-anchored rectangles. Read the
  // current list at paint time rather than an obsolete widget-build snapshot.
  // The optional provider is used only by the interactive chart; isolated
  // painters retain immutable snapshot semantics.
  final List<ChartPriceRectangle> Function()? _drawingsProvider;
  List<ChartPriceRectangle> get currentDrawings =>
      _drawingsProvider?.call() ?? drawings;
  final int? selectedIndex;
  final ChartViewport viewport;
  final ChartPriceScale scale;
  // The chart's painter already reads a live viewport during touch updates.
  // Use the same source for rectangle handles and time/price labels; a
  // standalone painter can still use its immutable snapshots.
  final ChartViewport Function()? _viewportProvider;
  final ChartPriceScale Function()? _scaleProvider;
  ChartViewport get currentViewport => _viewportProvider?.call() ?? viewport;
  ChartPriceScale get currentScale => _scaleProvider?.call() ?? scale;
  final int candleCount;
  final double plotWidth;
  final bool dark;
  final List<int> timestamps;
  final ChartTimeZone timeZone;
  // ChartScreen owns the measured text cache across gesture repaints.
  // Standalone renderers without a cache still dispose their paragraphs.
  final ChartTextLayoutCache? textCache;

  @override
  void paint(Canvas canvas, Size size) {
    if (candleCount == 0 || size.height < 30 || plotWidth <= 0) return;
    final viewport = currentViewport;
    final scale = currentScale;
    final chartHeight = scale.height;
    final activeDrawings = currentDrawings;
    for (var i = 0; i < activeDrawings.length; i++) {
      final drawing = activeDrawings[i];
      if (!drawing.visibleAt(candleCount)) continue;
      final area = PriceRectangleGeometry.rect(
          drawing, viewport, scale, candleCount, plotWidth);
      // A source-anchored rectangle which is wholly beyond the viewport's
      // price range needs no clipping, fill, border, or handle allocations
      // on every pan/pinch frame. Selected handles may show 11.5px of bleed
      // at the vertical edge, so retain that exact existing visible rim.
      if (!PriceRectangleGeometry.visibleInPlot(
          area, plotWidth, chartHeight, selected: selectedIndex == i)) {
        continue;
      }
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
        _priceTag(canvas, drawing.upper, scale.y(drawing.upper), size, scale);
        _priceTag(canvas, drawing.lower, scale.y(drawing.lower), size, scale);
        if (timestamps.length >= candleCount) {
          _timeTag(canvas, drawing.endIndex, area.center.dx, size, scale);
        }
      }
    }
  }

  void _timeTag(Canvas canvas, int index, double atX, Size size,
      ChartPriceScale scale) {
    if (index < 0 || index >= timestamps.length) return;
    final label = ChartRectangleTimeLabel.fromSource(
        timestamps[index], timeZone);
    // Match the original normal-weight, LTR 11.5px time tag exactly.
    final painter = textCache?.layout(
          label, Colors.white, 11.5, fontWeight: FontWeight.normal) ??
        (TextPainter(text: TextSpan(text: label,
            style: const TextStyle(color: Colors.white, fontSize: 11.5)),
            maxLines: 1, textDirection: TextDirection.ltr)..layout());
    final badgeWidth = math.min(plotWidth, painter.width + 16);
    final left = (atX - painter.width / 2 - 8).clamp(0.0,
        math.max(0.0, plotWidth - badgeWidth)).toDouble();
    final badgeHeight = math.min(21.0, size.height - scale.height);
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(left, scale.height + 1,
          badgeWidth, badgeHeight),
      const Radius.circular(2)), Paint()..color = TradeColors.rectangleAxisTag);
    // A narrow Android plot may be smaller than the selected time label.
    // Clip rather than allowing the text to cover the right price ruler.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
        left, scale.height + 1, badgeWidth, badgeHeight));
    painter.paint(canvas, Offset(left + 8, scale.height + 3));
    canvas.restore();
    if (textCache == null) painter.dispose();
  }

  void _priceTag(Canvas canvas, double value, double y, Size size,
      ChartPriceScale scale) {
    if (y < 0 || y > scale.height) return;
    final span = scale.maximum - scale.minimum;
    final decimals = span < .05 ? 5 : span < 1 ? 4 : span < 20 ? 2 : 1;
    final label = _price(value, decimals);
    const height = 19.0;
    final top = (y - height / 2)
        .clamp(0.0, math.max(0.0, scale.height - height)).toDouble();
    canvas.drawRect(Rect.fromLTWH(plotWidth, top,
        math.max(0.0, size.width - plotWidth), height),
      Paint()..color = TradeColors.rectangleAxisTag);
    // Label and font identity are unchanged; avoid relayout on every
    // pinch/pan frame while the selected rectangle remains in view.
    final painter = textCache?.layout(label, Colors.white, 10.5) ??
        (TextPainter(text: TextSpan(text: label,
          style: const TextStyle(fontSize: 10.5, color: Colors.white,
            fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr, maxLines: 1)..layout());
    painter.paint(canvas, Offset(plotWidth + 3, top + 2));
    if (textCache == null) painter.dispose();
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
      old.dark != dark || old.timestamps != timestamps ||
      old.timeZone != timeZone;
}
