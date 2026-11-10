import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_price_rectangle.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  const rectangle = ChartPriceRectangle(
    startIndex: 82, endIndex: 94, upper: 114, lower: 104);

  test('eight independent handles match screenshot geometry', () {
    final handles = PriceRectangleGeometry.handles(
        const Rect.fromLTWH(40, 60, 120, 90));
    expect(handles.length, 8);
    expect(handles[PriceRectangleHandle.topLeft], const Offset(40, 60));
    expect(handles[PriceRectangleHandle.topCenter], const Offset(100, 60));
    expect(handles[PriceRectangleHandle.bottomCenter], const Offset(100, 150));
    expect(handles[PriceRectangleHandle.middleRight], const Offset(160, 105));
  });

  test('each corner and mid-edge changes only its own price/time axes', () {
    final topLeft = rectangle.withHandle(
        PriceRectangleHandle.topLeft, 80, 117)!;
    expect((topLeft.startIndex, topLeft.endIndex), (80, 94));
    expect((topLeft.upper, topLeft.lower), (117, 104));
    final topCenter = rectangle.withHandle(
        PriceRectangleHandle.topCenter, 70, 118)!;
    expect((topCenter.startIndex, topCenter.endIndex), (82, 94));
    expect(topCenter.upper, 118);
    final middleRight = rectangle.withHandle(
        PriceRectangleHandle.middleRight, 97, 100)!;
    expect((middleRight.startIndex, middleRight.endIndex), (82, 97));
    expect((middleRight.upper, middleRight.lower), (114, 104));
    final bottomRight = rectangle.withHandle(
        PriceRectangleHandle.bottomRight, 98, 103)!;
    expect((bottomRight.endIndex, bottomRight.lower), (98, 103));
  });

  test('crossed prices and crossed bar indices are rejected', () {
    expect(rectangle.withHandle(PriceRectangleHandle.topLeft, 95, 115), isNull);
    expect(rectangle.withHandle(PriceRectangleHandle.topCenter, 90, 100), isNull);
    expect(rectangle.withHandle(PriceRectangleHandle.bottomRight, 98, 115), isNull);
    expect(rectangle.edited(strokeWidth: -1), isNull);
  });

  test('moving or prepending candles preserves real price/time anchors', () {
    final moved = rectangle.moved(3, -2)!;
    expect((moved.startIndex, moved.endIndex), (85, 97));
    expect((moved.upper, moved.lower), (112, 102));
    final shifted = moved.shifted(250);
    expect((shifted.startIndex, shifted.endIndex), (335, 347));
    expect((shifted.upper, shifted.lower), (112, 102));
    expect(rectangle.visibleAt(94), isFalse);
    expect(rectangle.visibleAt(95), isTrue);
  });

  test('hit-testing prioritizes handles and gives body a distinct drag', () {
    const viewport = ChartViewport(barWidth: 10);
    const scale = ChartPriceScale(100, 120, 200);
    final bounds = PriceRectangleGeometry.rect(
        rectangle, viewport, scale, 100, 400);
    final corner = PriceRectangleGeometry.hitTest(bounds.topLeft,
        [rectangle], viewport, scale, 100, 400);
    expect(corner?.$2, PriceRectangleHandle.topLeft);
    final interior = PriceRectangleGeometry.hitTest(bounds.center,
        [rectangle], viewport, scale, 100, 400);
    expect(interior?.$1, 0);
    expect(interior?.$2, isNull);
    expect(PriceRectangleGeometry.hitTest(const Offset(3, 3),
        [rectangle], viewport, scale, 100, 400), isNull);
  });

  testWidgets('isolated painter renders selected rectangle without market data',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(691, 1536);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 345.5, height: 690,
        child: RepaintBoundary(child: CustomPaint(
          key: const Key('selected-rectangle-preview'),
          painter: ChartPriceRectanglePainter(
            drawings: const [ChartPriceRectangle(
              startIndex: 88, endIndex: 97, upper: 142, lower: 137)],
            selectedIndex: 0,
            viewport: const ChartViewport(barWidth: 10),
            scale: const ChartPriceScale(100, 180, 666),
            candleCount: 100, plotWidth: 284.5, dark: false,
          ),
        )),
      ))),
    ));
    await tester.pump();
    expect(tester.getSize(find.byKey(
        const Key('selected-rectangle-preview'))), const Size(345.5, 690));
    await expectLater(find.byKey(const Key('selected-rectangle-preview')),
        matchesGoldenFile('goldens/selected_price_rectangle.png'));
  });
}
