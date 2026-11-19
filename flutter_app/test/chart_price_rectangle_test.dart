import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_price_rectangle.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  const rectangle = ChartPriceRectangle(
    startIndex: 82, endIndex: 94, upper: 114, lower: 104);

  test('rectangle time tag shares chart selected UTC / NY / device zone', () {
    final winter = DateTime.utc(2026, 11, 19, 2, 30)
        .millisecondsSinceEpoch;
    final summer = DateTime.utc(2026, 7, 15, 2, 30)
        .millisecondsSinceEpoch;
    expect(ChartRectangleTimeLabel.fromSource(winter, ChartTimeZone.utc),
        '19/11 02:30 UTC');
    expect(ChartRectangleTimeLabel.fromSource(
        winter, ChartTimeZone.newYork),
        '18/11 21:30 NY UTC-5');
    expect(ChartRectangleTimeLabel.fromSource(
        summer, ChartTimeZone.newYork),
        '14/07 22:30 NY UTC-4',
        reason: 'Real source instant gets the correct historical DST offset');

    final deviceDate = ChartTimeZone.device.displayDate(winter);
    String two(int value) => value.toString().padLeft(2, '0');
    expect(ChartRectangleTimeLabel.fromSource(
        winter, ChartTimeZone.device),
        '${two(deviceDate.day)}/${two(deviceDate.month)} '
        '${two(deviceDate.hour)}:${two(deviceDate.minute)} LOCAL');
    expect(ChartRectangleTimeLabel.fromSource(
        winter, ChartTimeZone.utc),
        isNot(ChartRectangleTimeLabel.fromSource(
            winter, ChartTimeZone.newYork)),
        reason: 'Changing chart display zone must change annotation labels');
  });

  test('offscreen rectangle painter culls thousands of vertical annotations',
      () {
    const viewport = ChartViewport(barWidth: 3);
    const scale = ChartPriceScale(100, 120, 200);
    const plotWidth = 259.0;
    final oldDrawings = List<ChartPriceRectangle>.generate(
      999, (i) => ChartPriceRectangle(
          startIndex: 940, endIndex: 980, upper: 145 + i.toDouble(),
          lower: 130 + i.toDouble()));
    final active = <ChartPriceRectangle>[
      ...oldDrawings,
      const ChartPriceRectangle(
          startIndex: 940, endIndex: 980, upper: 115, lower: 105),
    ];
    var painted = 0;
    for (var i = 0; i < active.length; i++) {
      final r = PriceRectangleGeometry.rect(
          active[i], viewport, scale, 1000, plotWidth);
      if (PriceRectangleGeometry.visibleInPlot(
          r, plotWidth, scale.height, selected: i == active.length - 1)) {
        painted++;
      }
    }
    expect(painted, 1,
        reason: '999 entirely above-price-range rectangles must not '
            'allocate clipped canvas layers every touch frame');
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, -20, 80, -5), 259, 200), isFalse);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, -20, 80, -5), 259, 200,
        selected: true), isTrue,
        reason: 'Selected 11.5px circular handle is still partially visible');
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, -30, 80, -12), 259, 200,
        selected: true), isFalse);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, 205, 80, 220), 259, 200,
        selected: true), isTrue);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, 212, 80, 230), 259, 200,
        selected: true), isFalse);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(double.nan, 10, 80, 100), 259, 200),
        isFalse);
    expect(PriceRectangleGeometry.visibleInPlot(
        const Rect.fromLTRB(0, 10, 80, 100), 0, 200), isFalse);
  });

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

  test('offscreen rectangle handles cannot steal visible chart touches', () {
    const viewport = ChartViewport(barWidth: 10);
    const scale = ChartPriceScale(100, 120, 200);
    const hidden = ChartPriceRectangle(
        startIndex: 50, endIndex: 62, upper: 114, lower: 104);
    final clipped = PriceRectangleGeometry.rect(
        hidden, viewport, scale, 100, 400);
    expect(clipped.right, -15);
    // Its hit radius reaches into the plot, but the painter clips the
    // ENTIRE rectangle because the final edge is offscreen.
    expect(PriceRectangleGeometry.hitTest(
        const Offset(5, 60), [hidden],
        viewport, scale, 100, 400), isNull);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(5, 100), [hidden],
        viewport, scale, 100, 400), isNull);

    // The first edge is partly clipped yet its 11.5px white handle really
    // is visible; touch access to the visible portion must remain.
    const visibleEdge = ChartPriceRectangle(
        startIndex: 63, endIndex: 75, upper: 114, lower: 104);
    final partiallyShown = PriceRectangleGeometry.rect(
        visibleEdge, viewport, scale, 100, 400);
    expect(partiallyShown.left, -5);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(4, 60), [visibleEdge],
        viewport, scale, 100, 400)?.$2,
        PriceRectangleHandle.topLeft);
  });

  test('time and price axes cannot select rectangle handles', () {
    const viewport = ChartViewport(barWidth: 10, rightMarginBars: 0);
    const scale = ChartPriceScale(100, 120, 200);
    const atRight = ChartPriceRectangle(
        startIndex: 90, endIndex: 99, upper: 114, lower: 104);
    expect(PriceRectangleGeometry.rect(
        atRight, viewport, scale, 100, 400).right, 395);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(404, 60), [atRight],
        viewport, scale, 100, 400), isNull,
        reason: 'The price ruler is reserved for its own gestures');
    expect(PriceRectangleGeometry.hitTest(
        const Offset(394, 60), [atRight],
        viewport, scale, 100, 400)?.$2,
        PriceRectangleHandle.topRight);

    const nearTimeAxis = ChartPriceRectangle(
        startIndex: 90, endIndex: 99, upper: 107, lower: 100.5);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(395, 205), [nearTimeAxis],
        viewport, scale, 100, 400), isNull,
        reason: 'The bottom 24dp belongs to the time ruler, not drawings');
    expect(PriceRectangleGeometry.hitTest(
        const Offset(395, 194), [nearTimeAxis],
        viewport, scale, 100, 400)?.$2,
        PriceRectangleHandle.bottomRight);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(double.nan, 110), [atRight],
        viewport, scale, 100, 400), isNull);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(100, double.infinity), [atRight],
        viewport, scale, 100, 400), isNull);
  });

  test('large historical rectangle collection keeps topmost visible hit',
      () {
    const viewport = ChartViewport(barWidth: 3);
    const scale = ChartPriceScale(100, 120, 200);
    final drawings = List<ChartPriceRectangle>.generate(
      999, (index) => ChartPriceRectangle(
        startIndex: index, endIndex: index + 1,
        upper: 114, lower: 104),
    );
    final target = PriceRectangleGeometry.rect(
        drawings.last, viewport, scale, 1000, 300);
    expect(target.right, inInclusiveRange(0, 300));
    final selected = PriceRectangleGeometry.hitTest(
      target.topRight, drawings, viewport, scale, 1000, 300);
    expect(selected?.$1, 998);
    // At only 3px/bar the two visible corner handles overlap; the
    // existing accessible hit priority picks the left corner first.
    expect(selected?.$2, PriceRectangleHandle.topLeft);
    expect(PriceRectangleGeometry.hitTest(
        const Offset(20, 198), drawings,
        viewport, scale, 1000, 300), isNull,
        reason: 'Thousands of offscreen handles stay untouchable');
    // Replay prefix cannot expose a drawing ending beyond revealed bars.
    expect(PriceRectangleGeometry.hitTest(
        target.topRight, [drawings.last],
        viewport, scale, 999, 300), isNull);
  });

  testWidgets('isolated painter renders selected rectangle without market data',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(691, 1536);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 345.5, height: 690,
        child: RepaintBoundary(child: ColoredBox(
          key: const Key('selected-rectangle-preview'),
          color: Colors.white,
          child: CustomPaint(
            painter: ChartPriceRectanglePainter(
              drawings: const [ChartPriceRectangle(
                startIndex: 88, endIndex: 97, upper: 144.3, lower: 139.7)],
              selectedIndex: 0,
              viewport: const ChartViewport(barWidth: 10, scrollBars: .5),
              scale: const ChartPriceScale(100, 180, 666),
              candleCount: 100, plotWidth: 284.5, dark: false,
            ),
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
