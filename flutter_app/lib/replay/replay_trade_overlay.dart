import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../chart/chart_viewport.dart';
import 'replay_training_session.dart';

/// Exact pixels for a practice trade that exists on the currently revealed
/// Replay prefix. This is presentation only: never modifies source OHLC,
/// performs fills or submits an order to a broker.
@immutable
class ReplayTradeOverlayMark {
  const ReplayTradeOverlayMark({
    required this.trade,
    required this.entryX,
    required this.endX,
    required this.entryY,
    required this.exitY,
    required this.stopY,
    required this.targetY,
  });

  final ReplayTrainingTrade trade;
  final double entryX;
  final double endX;
  final double entryY;
  final double? exitY;
  final double? stopY;
  final double? targetY;
}

/// Uses the SAME viewport and price scale as the real chart painter.
/// The end point never extends into a future (unrevealed) candle.
class ReplayTradeOverlayLayout {
  const ReplayTradeOverlayLayout._();

  /// Paint bounds are a finite, narrow Android chart viewport, while the
  /// market source may contain 200k+ candles. A practice trade beginning on
  /// an old candle can span MILLIONS of offscreen pixels. Skia's clipRect
  /// clips the *result*, not the Dart loop that previously created 160k+
  /// dashed strokes per frame for each long open SL/TP line.
  ///
  /// Keep the dash phase anchored at the original entry x even when most
  /// of that line is offscreen. Skip whole hidden periods arithmetically:
  /// the number of yielded marks is O(plotWidth / 12), independent of the
  /// number of archived source candles or scroll distance.
  static Iterable<(double, double)> visibleDashSegments({
    required double x1,
    required double x2,
    required double plotWidth,
  }) sync* {
    if (!x1.isFinite || !x2.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0) return;
    const dashPeriod = 12.0;
    const dashLength = 7.0;
    final left = math.min(x1, x2);
    final right = math.min(math.max(x1, x2), plotWidth);
    if (right <= 0 || left >= plotWidth || right <= left) return;
    // x + dashLength must be positive to be even partially visible.
    final first = math.max(0,
        ((-left - dashLength) / dashPeriod).ceil());
    for (var k = first; ; k++) {
      final start = left + k * dashPeriod;
      if (start >= right) break;
      final clippedStart = math.max(0.0, start);
      final clippedEnd = math.min(right, start + dashLength);
      if (clippedEnd > clippedStart) {
        yield (clippedStart, clippedEnd);
      }
    }
  }

  /// All horizontal Replay practice overlays must share the same plot
  /// clipping, including their solid entry and result segments. This avoids
  /// passing multi-million-pixel stroke endpoints into the raster backend.
  static (double, double)? visibleStroke({
    required double x1,
    required double x2,
    required double plotWidth,
  }) {
    if (!x1.isFinite || !x2.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0) return null;
    final left = math.max(0.0, math.min(x1, x2));
    final right = math.min(plotWidth, math.max(x1, x2));
    if (left >= right) return null;
    return (left, right);
  }

  static List<ReplayTradeOverlayMark> visible({
    required List<ReplayTrainingTrade> trades,
    required ChartViewport viewport,
    required ChartPriceScale scale,
    required int candleCount,
    required double plotWidth,
  }) {
    if (trades.isEmpty || candleCount < 1 ||
        !plotWidth.isFinite || plotWidth <= 0) {
      return const [];
    }
    final marks = <ReplayTradeOverlayMark>[];
    for (final trade in trades) {
      if (trade.entryIndex < 0 || trade.entryIndex >= candleCount ||
          !trade.entryPrice.isFinite) {
        continue;
      }

      // A closed trade can end on an earlier candle; an open trade stops at
      // the LAST REVEALED candle. Invalid future exit data is not drawn.
      final closed = trade.exitIndex != null &&
          trade.exitIndex! >= trade.entryIndex &&
          trade.exitIndex! < candleCount;
      final endIndex = closed ? trade.exitIndex! : candleCount - 1;

      final entryX = viewport.chartX(
          index: trade.entryIndex,
          candleCount: candleCount,
          plotWidth: plotWidth);
      final endX = viewport.chartX(
          index: endIndex,
          candleCount: candleCount,
          plotWidth: plotWidth);
      // Skip off-screen and nonfinite geometry before reaching the renderer.
      if (!entryX.isFinite || !endX.isFinite ||
          math.max(entryX, endX) < -8 ||
          math.min(entryX, endX) > plotWidth + 8) {
        continue;
      }

      marks.add(ReplayTradeOverlayMark(
        trade: trade,
        entryX: entryX,
        endX: endX,
        entryY: scale.y(trade.entryPrice),
        exitY: closed && trade.exitPrice != null &&
                trade.exitPrice!.isFinite
            ? scale.y(trade.exitPrice!)
            : null,
        stopY: trade.stopLoss != null && trade.stopLoss!.isFinite
            ? scale.y(trade.stopLoss!)
            : null,
        targetY: trade.takeProfit != null && trade.takeProfit!.isFinite
            ? scale.y(trade.takeProfit!)
            : null,
      ));
    }
    return List<ReplayTradeOverlayMark>.unmodifiable(marks);
  }
}

/// Draws independent, locally simulated entry / SL / TP segments per trade.
/// Neither price lines nor markers are extended across unrelated trades.
/// This paint layer is clipped to the candle plot; the price axis is untouched.
class ReplayTradeOverlayPainter extends CustomPainter {
  ReplayTradeOverlayPainter({
    required this.trades,
    required this.viewport,
    required this.scale,
    required this.candleCount,
    required this.plotWidth,
    ChartViewport Function()? viewportProvider,
    ChartPriceScale Function()? scaleProvider,
    Listenable? repaint,
  }) : _viewportProvider = viewportProvider,
       _scaleProvider = scaleProvider,
       super(repaint: repaint);

  final List<ReplayTrainingTrade> trades;
  // The snapshots are for a normal widget rebuild/shouldRepaint comparison.
  // During gestures, the chart's shared repaint notifier supplies the latest
  // viewport and the matching auto-scale without rebuilding the toolbar.
  final ChartViewport viewport;
  final ChartPriceScale scale;
  final ChartViewport Function()? _viewportProvider;
  final ChartPriceScale Function()? _scaleProvider;
  final int candleCount;
  final double plotWidth;

  ChartViewport get currentViewport => _viewportProvider?.call() ?? viewport;
  ChartPriceScale get currentScale => _scaleProvider?.call() ?? scale;

  static const _buy = Color(0xFF178F71);
  static const _sell = Color(0xFFE05050);
  static const _stop = Color(0xFFDA4040);
  static const _target = Color(0xFF0D968A);

  static void _dashed(Canvas canvas, double x1, double x2, double y,
      Color color, double plotWidth) {
    if (!x1.isFinite || !x2.isFinite || !y.isFinite ||
        !plotWidth.isFinite || plotWidth <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: .9)
      ..strokeWidth = 1.35;
    if ((x2 - x1).abs() < 3) {
      final left = math.min(x1, x2);
      if (left >= 0 && left <= plotWidth) {
        canvas.drawCircle(Offset(left, y), 2.0, paint);
      }
      return;
    }
    for (final (start, end) in ReplayTradeOverlayLayout.visibleDashSegments(
      x1: x1, x2: x2, plotWidth: plotWidth,
    )) {
      canvas.drawLine(Offset(start, y), Offset(end, y), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 24 || !plotWidth.isFinite ||
        plotWidth <= 0 || candleCount < 1) return;
    final plotHeight = size.height - 24;
    final marks = ReplayTradeOverlayLayout.visible(
        trades: trades,
        viewport: currentViewport,
        scale: currentScale,
        candleCount: candleCount,
        plotWidth: plotWidth);
    if (marks.isEmpty) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, plotWidth, plotHeight));
    for (final mark in marks) {
      final color = mark.trade.side == ReplaySide.buy ? _buy : _sell;
      final line = ReplayTradeOverlayLayout.visibleStroke(
          x1: mark.entryX, x2: mark.endX, plotWidth: plotWidth);
      if (line != null && mark.entryY.isFinite) {
        canvas.drawLine(
          Offset(line.$1, mark.entryY),
          Offset(line.$2, mark.entryY),
          Paint()..color = color.withValues(alpha: .9)..strokeWidth = 1.8,
        );
      }
      if (mark.stopY != null) {
        _dashed(canvas, mark.entryX, mark.endX,
            mark.stopY!, _stop, plotWidth);
      }
      if (mark.targetY != null) {
        _dashed(canvas, mark.entryX, mark.endX,
            mark.targetY!, _target, plotWidth);
      }
      if (mark.entryX >= 0 && mark.entryX <= plotWidth &&
          mark.entryY.isFinite) {
        canvas.drawCircle(
            Offset(mark.entryX, mark.entryY), 4,
            Paint()..color = color);
        canvas.drawCircle(
            Offset(mark.entryX, mark.entryY), 4,
            Paint()..color = const Color(0xFFFFFFFF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
      if (mark.exitY != null && mark.exitY!.isFinite &&
          mark.endX >= 0 && mark.endX <= plotWidth) {
        canvas.drawCircle(
          Offset(mark.endX, mark.exitY!), 4,
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.drawCircle(
          Offset(mark.endX, mark.exitY!), 4,
          Paint()..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReplayTradeOverlayPainter old) =>
      old.viewport != viewport ||
      old.scale.minimum != scale.minimum ||
      old.scale.maximum != scale.maximum ||
      old.scale.height != scale.height ||
      old.candleCount != candleCount ||
      old.plotWidth != plotWidth ||
      !listEquals(old.trades, trades);
}
