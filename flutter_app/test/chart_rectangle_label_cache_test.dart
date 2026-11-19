import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_price_rectangle.dart';
import 'package:tradelab_flutter/chart/chart_text_layout_cache.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const selectedRectangle = ChartPriceRectangle(
      startIndex: 88, endIndex: 97, upper: 144.3, lower: 139.7);
  final timestamps = List<int>.generate(
      100, (index) => 1700000000000 + index * 60000);

  Widget canvas(ChartTextLayoutCache cache, {
    double scrollBars = .5,
    int? selectedIndex = 0,
    List<int>? sourceTimestamps,
  }) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(
    width: 345.5,
    height: 690,
    child: CustomPaint(
      painter: ChartPriceRectanglePainter(
        drawings: const [selectedRectangle],
        selectedIndex: selectedIndex,
        viewport: ChartViewport(barWidth: 10, scrollBars: scrollBars),
        scale: const ChartPriceScale(100, 180, 666),
        candleCount: 100,
        plotWidth: 284.5,
        dark: false,
        timestamps: sourceTimestamps ?? timestamps,
        textCache: cache,
      ),
    ),
  ))));

  testWidgets('selected rectangle reuses price and time tags during panning',
      (tester) async {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(canvas(cache));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(cache.length, 3,
        reason: 'Two broker price tags and one source-timestamp tag');
    final upper = cache.layout('144.3', Colors.white, 10.5);
    final lower = cache.layout('139.7', Colors.white, 10.5);
    final sourceTime = DateTime.fromMillisecondsSinceEpoch(
        timestamps[97], isUtc: true);
    final timeLabel = '${sourceTime.day.toString().padLeft(2, '0')}/'
        '${sourceTime.month.toString().padLeft(2, '0')} '
        '${sourceTime.hour.toString().padLeft(2, '0')}:'
        '${sourceTime.minute.toString().padLeft(2, '0')} UTC';
    final timePainter = cache.layout(timeLabel, Colors.white, 11.5,
        fontWeight: FontWeight.normal);
    expect(cache.length, 3);

    await tester.pumpWidget(canvas(cache, scrollBars: 1.5));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(cache.length, 3);
    expect(identical(cache.layout('144.3', Colors.white, 10.5), upper), isTrue);
    expect(identical(cache.layout('139.7', Colors.white, 10.5), lower), isTrue);
    expect(identical(cache.layout(timeLabel, Colors.white, 11.5,
        fontWeight: FontWeight.normal), timePainter), isTrue);
    expect((timePainter.text! as TextSpan).style!.fontWeight,
        FontWeight.normal);
  });

  testWidgets('no future rectangle time label without verified time prefix',
      (tester) async {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(canvas(cache,
        sourceTimestamps: timestamps.sublist(0, 99)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(cache.length, 2,
        reason: 'A missing last source timestamp may not be invented');
  });

  testWidgets('unselected rectangle does not allocate text labels',
      (tester) async {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    await tester.pumpWidget(canvas(cache, selectedIndex: null));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(cache.length, 0);
  });

  testWidgets('live rectangle viewport and scale repaint without rebuild',
      (tester) async {
    final redraw = ValueNotifier<int>(0);
    final cache = ChartTextLayoutCache();
    addTearDown(redraw.dispose);
    addTearDown(cache.clear);
    var currentViewport = const ChartViewport(
        barWidth: 10, scrollBars: .5);
    var currentScale = const ChartPriceScale(100, 180, 666);
    var viewportReads = 0;
    var scaleReads = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: SizedBox(
        width: 345.5,
        height: 690,
        child: CustomPaint(
          key: const Key('live-rectangle-canvas'),
          painter: ChartPriceRectanglePainter(
            drawings: const [selectedRectangle],
            selectedIndex: 0,
            viewport: currentViewport,
            scale: currentScale,
            viewportProvider: () {
              viewportReads++;
              return currentViewport;
            },
            scaleProvider: () {
              scaleReads++;
              return currentScale;
            },
            repaint: redraw,
            candleCount: 100,
            plotWidth: 284.5,
            dark: false,
            timestamps: timestamps,
            textCache: cache,
          ),
        ),
      )),
    )));
    await tester.pump();
    final finder = find.byKey(const Key('live-rectangle-canvas'));
    final initialPainter = tester.widget<CustomPaint>(finder)
        .painter! as ChartPriceRectanglePainter;
    expect(initialPainter.currentViewport, currentViewport);
    expect(initialPainter.currentScale, currentScale);
    expect(cache.length, 3);
    final initialRect = PriceRectangleGeometry.rect(
        selectedRectangle, currentViewport, currentScale, 100, 284.5);
    final initialViewportReads = viewportReads;
    final initialScaleReads = scaleReads;

    currentViewport = const ChartViewport(
        barWidth: 10, scrollBars: 3.5);
    currentScale = const ChartPriceScale(90, 170, 666);
    redraw.value++;
    await tester.pump();
    final updatedPainter = tester.widget<CustomPaint>(finder)
        .painter! as ChartPriceRectanglePainter;
    expect(identical(initialPainter, updatedPainter), isTrue,
        reason: 'Only a repaint occurred: no Flutter widget rebuild');
    expect(viewportReads, greaterThan(initialViewportReads));
    expect(scaleReads, greaterThan(initialScaleReads));
    expect(updatedPainter.currentViewport, currentViewport);
    expect(updatedPainter.currentScale, currentScale);
    final movedRect = PriceRectangleGeometry.rect(
        selectedRectangle, updatedPainter.currentViewport,
        updatedPainter.currentScale, 100, 284.5);
    expect(movedRect.left, greaterThan(initialRect.left));
    expect(movedRect.top, lessThan(initialRect.top));
    expect(cache.length, 3,
        reason: 'Existing measured price/time labels remain reused');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a rectangle repaints its live source anchors only',
      (tester) async {
    final candleSignal = ValueNotifier<int>(0);
    final rectangleSignal = ValueNotifier<int>(0);
    final merged = Listenable.merge([candleSignal, rectangleSignal]);
    final cache = ChartTextLayoutCache();
    addTearDown(candleSignal.dispose);
    addTearDown(rectangleSignal.dispose);
    addTearDown(cache.clear);
    var candleNotifications = 0;
    candleSignal.addListener(() => candleNotifications++);
    final liveDrawings = <ChartPriceRectangle>[selectedRectangle];
    var liveReads = 0;
    const viewport = ChartViewport(barWidth: 10, scrollBars: .5);
    const scale = ChartPriceScale(100, 180, 666);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: Column(children: [
        const Text('شارت TradeLab', key: Key('stable-chart-header')),
        SizedBox(width: 345.5, height: 690,
          child: RepaintBoundary(child: CustomPaint(
            key: const Key('independently-repainted-rectangle'),
            painter: ChartPriceRectanglePainter(
              // Keep a snapshot for builds, but live drag coordinates for
              // each repaint. The painter object must not be recreated.
              drawings: List<ChartPriceRectangle>.unmodifiable(liveDrawings),
              drawingsProvider: () {
                liveReads++;
                return liveDrawings;
              },
              selectedIndex: 0,
              viewport: viewport, scale: scale, repaint: merged,
              candleCount: 100, plotWidth: 284.5, dark: false,
              timestamps: timestamps, textCache: cache,
            ),
          )),
        ),
      ]),
    ))));
    await tester.pump();
    final overlay = find.byKey(const Key('independently-repainted-rectangle'));
    final header = find.byKey(const Key('stable-chart-header'));
    final initialHeaderWidget = tester.widget(header);
    final originalPainter = tester.widget<CustomPaint>(overlay)
        .painter! as ChartPriceRectanglePainter;
    expect(originalPainter.currentDrawings.single, selectedRectangle);
    expect(cache.length, 3);
    final initialReads = liveReads;
    final initialBounds = PriceRectangleGeometry.rect(
        selectedRectangle, viewport, scale, 100, 284.5);

    // Simulate the chart's onScaleUpdate: mutate only the real drawing
    // and notify the overlay. No setState or candle signal is involved.
    liveDrawings[0] = selectedRectangle.moved(2, 3)!;
    rectangleSignal.value++;
    await tester.pump();
    final afterDrag = tester.widget<CustomPaint>(overlay)
        .painter! as ChartPriceRectanglePainter;
    expect(identical(afterDrag, originalPainter), isTrue,
        reason: 'Touching a drawing must not rebuild the chart tree');
    expect(identical(tester.widget(header), initialHeaderWidget), isTrue);
    expect(candleNotifications, 0,
        reason: 'A rectangle move does not invalidate candle rendering');
    expect(liveReads, greaterThan(initialReads),
        reason: 'Overlay paints current anchors, not stale build snapshots');
    expect(afterDrag.drawings.single.upper, 144.3,
        reason: 'The original snapshot remains immutable');
    expect(afterDrag.currentDrawings.single.upper, 147.3);
    expect(afterDrag.currentDrawings.single.lower, 142.7);
    final newBounds = PriceRectangleGeometry.rect(
        afterDrag.currentDrawings.single, viewport, scale, 100, 284.5);
    expect(newBounds.left, greaterThan(initialBounds.left));
    expect(newBounds.top, lessThan(initialBounds.top));
    expect(cache.length, 6,
        reason: 'Only new price and real UTC time tags are measured');
    expect(tester.takeException(), isNull);
  });

}
