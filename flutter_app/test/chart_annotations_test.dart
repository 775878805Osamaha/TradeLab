import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_annotations.dart';

void main() {
  test('older pages preserve the same market-price drawing anchors', () {
    const drawing = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(12, 4050.25),
      end: ChartAnchor(24, 4091.75),
    );
    final shifted = drawing.shifted(1000);
    expect(shifted.start.index, 1012);
    expect(shifted.end.index, 1024);
    expect(shifted.start.price, 4050.25);
    expect(shifted.end.price, 4091.75);
  });

  test('Fibonacci derives levels only from selected past prices', () {
    const drawing = ChartPattern(
      tool: ChartDrawingTool.fibonacci,
      start: ChartAnchor(10, 4000),
      end: ChartAnchor(20, 4100),
    );
    expect(drawing.fibonacciPrice(0), 4000);
    expect(drawing.fibonacciPrice(.5), 4050);
    expect(drawing.fibonacciPrice(1), 4100);
  });

  test('Replay does not reveal a drawing anchored to future bars', () {
    const drawing = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(16, 4020),
      end: ChartAnchor(40, 4070),
    );
    expect(drawing.visibleAt(20), isFalse);
    expect(drawing.visibleAt(40), isFalse);
    expect(drawing.visibleAt(41), isTrue);
  });

  test('moving and styling drawings preserve the original object', () {
    const first = ChartPattern(
      tool: ChartDrawingTool.trendLine,
      start: ChartAnchor(4, 12.5),
      end: ChartAnchor(8, 14.5),
    );
    final edited = first.moved(2, 1.5).styled(
      colorValue: 0xFFE34A4A, strokeWidth: 3,
    );
    expect(edited.start.index, 6);
    expect(edited.start.price, 14);
    expect(edited.end.index, 10);
    expect(edited.end.price, 16);
    expect(edited.strokeWidth, 3);
    expect(edited.colorValue, 0xFFE34A4A);
    expect(first.start.price, 12.5);
  });

  test('rebasing a drawing preserves historical prices and style', () {
    const original = ChartPattern(
      tool: ChartDrawingTool.fibonacci,
      start: ChartAnchor(5, 4011.25),
      end: ChartAnchor(12, 4045.5),
      colorValue: 0xFFE8A426,
      strokeWidth: 2.5,
      showLabels: false,
    );
    final rebased = original.reanchored(22, 37);
    expect(rebased.start.index, 22);
    expect(rebased.end.index, 37);
    expect(rebased.start.price, 4011.25);
    expect(rebased.end.price, 4045.5);
    expect(rebased.colorValue, 0xFFE8A426);
    expect(rebased.strokeWidth, 2.5);
    expect(rebased.showLabels, false);
  });

  test('weak OHLC magnet only snaps nearby, strong snaps any price', () {
    const prices = [4010.0, 4020.0, 4000.0, 4012.0];
    expect(snapDrawingPrice(requestedPrice: 4011.7, ohlc: prices,
      mode: ChartMagnetMode.off, weakPriceTolerance: 1), 4011.7);
    expect(snapDrawingPrice(requestedPrice: 4011.7, ohlc: prices,
      mode: ChartMagnetMode.weak, weakPriceTolerance: 1), 4012);
    expect(snapDrawingPrice(requestedPrice: 4017, ohlc: prices,
      mode: ChartMagnetMode.weak, weakPriceTolerance: 1), 4017);
    expect(snapDrawingPrice(requestedPrice: 4017, ohlc: prices,
      mode: ChartMagnetMode.strong, weakPriceTolerance: 1), 4020);
  });
}
