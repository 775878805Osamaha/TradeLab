import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';
import 'package:tradelab_flutter/chart/chart_info_line_stats.dart';

void main() {
  const line = ChartPattern(
    tool: ChartDrawingTool.infoLine,
    start: ChartAnchor(10, 200),
    end: ChartAnchor(14, 225),
  );
  final times = List<int>.generate(20,
      (i) => 1700000000000 + i * 15 * 60000);
  ChartInfoLineStats? stats(ChartPattern drawing, {
      int revealedCount = 20, List<int>? timestamps,
      Offset start = const Offset(30, 200),
      Offset end = const Offset(130, 100),
  }) => ChartInfoLineStats.fromVisible(
    drawing: drawing, revealedCount: revealedCount,
    timestampsUtcMs: timestamps ?? times,
    startScreen: start, endScreen: end);

  test('two real source anchors show delta, percent, bars, UTC, angle', () {
    final s = stats(line);
    expect(s, isNotNull);
    expect(s!.priceChange, 25);
    expect(s.percentChange, 12.5);
    expect(s.bars, 4);
    expect(s.elapsedMs, 60 * 60000);
    expect(s.elapsedLabel, '1س 0د');
    expect(s.angleDegrees, closeTo(45, 1e-8));
    expect(s.valueLabel(2), 'Δ 25.00  (12.50%)');
    expect(s.durationLabel, contains('4 شمعة'));
    expect(s.durationLabel, contains('1س 0د'));
    expect(s.durationLabel, contains('45.0°'));
    expect(line.start.price, 200);
    expect(line.end.price, 225);
  });

  test('decreasing historical price is correctly signed and source anchored',
      () {
    const down = ChartPattern(
      tool: ChartDrawingTool.infoLine,
      start: ChartAnchor(2, 1000),
      end: ChartAnchor(6, 890),
      showLabels: false,
    );
    final s = stats(down,
        start: const Offset(100, 20), end: const Offset(170, 70));
    expect(s, isNotNull);
    expect(s!.priceChange, -110);
    expect(s.percentChange, -11);
    expect(s.bars, 4);
    expect(s.angleDegrees, lessThan(0));
    expect(s.valueLabel(2), 'Δ -110.00  (-11.00%)');
    expect(s.durationLabel, contains('4 شمعة'));
    expect(down.showLabels, isFalse);
    expect(down.start.price, 1000);
  });

  test('Replay cutoff protects both future source bars and timestamps', () {
    expect(stats(line, revealedCount: 14), isNull,
        reason: 'End index 14 is unrevealed when count is 14');
    expect(stats(line, revealedCount: 15), isNotNull);
    expect(stats(line, revealedCount: 0), isNull);
    expect(stats(line, timestamps: times.take(12).toList()), isNull);
    expect(stats(line, timestamps: times.take(15).toList()), isNotNull);
    final badTimes = times.toList()..[14] = 0;
    expect(stats(line, timestamps: badTimes), isNull);
  });

  test('zero-base, invalid geometry and non-info tools stay safe', () {
    const zero = ChartPattern(
      tool: ChartDrawingTool.infoLine,
      start: ChartAnchor(10, 0),
      end: ChartAnchor(14, 2500),
    );
    final s = stats(zero)!;
    expect(s.percentChange, isNull);
    expect(s.valueLabel(2), 'Δ 2,500.00  (—)');
    expect(stats(line, start: const Offset(double.nan, 100)), isNull);
    expect(stats(line, end: const Offset(double.infinity, 100)), isNull);
    const other = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(10, 200),
      end: ChartAnchor(14, 225),
    );
    expect(stats(other), isNull);
    const invalidIndex = ChartPattern(
      tool: ChartDrawingTool.infoLine,
      start: ChartAnchor(-1, 200),
      end: ChartAnchor(14, 225),
    );
    expect(stats(invalidIndex), isNull);
  });

  test('source index rebase preserves real price delta and elapsed UTC', () {
    final moved = line.shifted(120000);
    final moreHistory = List<int>.generate(120020,
        (i) => 1700000000000 + (i - 120000) * 15 * 60000);
    final s = stats(moved,
        revealedCount: 120020, timestamps: moreHistory);
    expect(s, isNotNull);
    expect(s!.bars, 4);
    expect(s.elapsedMs, 3600000);
    expect(s.priceChange, 25);
    expect(moved.start.index, 120010);
    expect(moved.end.index, 120014);
    expect(moved.visibleAt(120014), isFalse);
    expect(moved.visibleAt(120015), isTrue);
  });

  test('UTC market closure is real elapsed time, not bars * timeframe', () {
    final unusual = times.toList()..[14] += 12 * 60 * 60 * 1000;
    final s = stats(line, timestamps: unusual)!;
    expect(s.bars, 4);
    expect(s.elapsedLabel, '0ي 13س 0د'.replaceFirst('0ي ', ''),
        reason: 'UTC gap is preserved even if no candles existed for 12h');
    expect(s.elapsedMs, 13 * 60 * 60 * 1000);
  });
}
