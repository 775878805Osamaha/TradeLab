import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/replay/replay_start_resolver.dart';

void main() {
  final bars = [100000, 160000, 220000, 280000, 340000];

  test('only broker-timestamped completed bars qualify for Replay', () {
    expect(ReplayStartResolver.hasVerifiedTimes(bars, 5), isTrue);
    expect(ReplayStartResolver.hasVerifiedTimes(bars, 6), isFalse);
    expect(ReplayStartResolver.hasVerifiedTimes([10, 9, 20], 3), isFalse);
    expect(ReplayStartResolver.hasVerifiedTimes([10, 10, 20], 3), isTrue);
    expect(ReplayStartResolver.hasVerifiedTimes([], 0), isFalse);
  });

  test('selection remains bar-anchored when zoom and pan change chart x', () {
    const viewport = ChartViewport(barWidth: 10, scrollBars: 0);
    final x = viewport.chartX(index: 2, candleCount: 5, plotWidth: 300);
    final index = ReplayStartResolver.atX(
      viewport: viewport, x: x, plotWidth: 300, candleCount: 5,
      completedCount: 5, fallbackIndex: 0);
    expect(index, 2);
    final zoomed = viewport.pinch(
      scale: 2, initialFocalX: x, currentFocalX: x,
      plotWidth: 300, candleCount: 5);
    expect(zoomed.chartX(index: index, candleCount: 5, plotWidth: 300),
        closeTo(x, .001));
    expect(ReplayStartResolver.timestampAt(bars, index, 5), 220000);
  });

  test('date in real market gap seeks previous verified bar only', () {
    expect(ReplayStartResolver.atOrBefore(bars, 5, 219999), 1);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 220000), 2);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 300000), 3);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 0), -1);
    expect(ReplayStartResolver.atOrBefore(bars, 5, 999999), 3,
        reason: 'Last bar excluded: Replay must retain a future step');
  });

  test('pixel selection never targets off-canvas future whitespace', () {
    const viewport = ChartViewport(barWidth: 12, scrollBars: -8);
    expect(ReplayStartResolver.atX(
      viewport: viewport, x: 299, plotWidth: 300, candleCount: 5,
      completedCount: 5, fallbackIndex: 1), 1);
    expect(ReplayStartResolver.atX(
      viewport: viewport, x: -100, plotWidth: 300, candleCount: 5,
      completedCount: 5, fallbackIndex: 1), 1);
  });
}
