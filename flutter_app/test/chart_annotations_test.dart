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
}
