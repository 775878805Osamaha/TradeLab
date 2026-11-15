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

  static List<ReplayTradeOverlayMark> visible({
    required List<ReplayTrainingTrade> trades,
    required ChartViewport viewport,
    required ChartPriceScale scale,
    required int candleCount,
    required double plotWidth,
  }) {
    if (trades.isEmpty || candleCount < 1 || plotWidth <= 0) {
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
      // Skip off-screen trades rather than paying the cost to paint them.
      if (math.max(entryX, endX) < -8 ||
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
  });

  final List<ReplayTrainingTrade> trades;
  final ChartViewport viewport;
  final ChartPriceScale scale;
  final int candleCount;
  final double plotWidth;

  static const _buy = Color(0xFF178F71);
  static const _sell = Color(0xFFE05050);
  static const _stop = Color(0xFFDA4040);
  static const _target = Color(0xFF0D968A);

  static void _dashed(Canvas canvas, double x1, double x2, double y,
      Color color) {
    final left = math.min(x1, x2);
    final right = math.max(x1, x2);
    final paint = Paint()
      ..color = color.withValues(alpha: .9)
      ..strokeWidth = 1.35;
    if (right - left < 3) {
      canvas.drawCircle(Offset(left, y), 2.0, paint);
      return;
    }
    for (var x = left; x < right; x += 12) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + 7, right), y), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 24 || plotWidth <= 0 || candleCount < 1) return;
    final plotHeight = size.height - 24;
    final marks = ReplayTradeOverlayLayout.visible(
        trades: trades,
        viewport: viewport,
        scale: scale,
        candleCount: candleCount,
        plotWidth: plotWidth);
    if (marks.isEmpty) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, plotWidth, plotHeight));
    for (final mark in marks) {
      final color = mark.trade.side == ReplaySide.buy ? _buy : _sell;
      canvas.drawLine(
        Offset(mark.entryX, mark.entryY),
        Offset(mark.endX, mark.entryY),
        Paint()..color = color.withValues(alpha: .9)..strokeWidth = 1.8,
      );
      if (mark.stopY != null) {
        _dashed(canvas, mark.entryX, mark.endX, mark.stopY!, _stop);
      }
      if (mark.targetY != null) {
        _dashed(canvas, mark.entryX, mark.endX, mark.targetY!, _target);
      }
      canvas.drawCircle(
          Offset(mark.entryX, mark.entryY), 4,
          Paint()..color = color);
      canvas.drawCircle(
          Offset(mark.entryX, mark.entryY), 4,
          Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (mark.exitY != null) {
        canvas.drawCircle(
          Offset(mark.endX, mark.exitY!), 4,
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.drawCircle(
          Offset(mark.endX, mark.exitY!), 4,
          Paint()..color = color..style = PaintingStyle.stroke
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
