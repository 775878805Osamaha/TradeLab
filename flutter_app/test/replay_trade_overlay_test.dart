import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/replay/replay_trade_overlay.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';

void main() {
  const viewport = ChartViewport(barWidth: 10);
  const scale = ChartPriceScale(90, 120, 300);

  const openBuy = ReplayTrainingTrade(
    id: 1,
    side: ReplaySide.buy,
    entryIndex: 2,
    entryPrice: 103,
    quantity: 1,
    stopLoss: 98,
    takeProfit: 112,
  );

  test('no future entry or SL/TP marker is exposed before its candle', () {
    final hidden = ReplayTradeOverlayLayout.visible(
      trades: [openBuy],
      viewport: viewport,
      scale: scale,
      candleCount: 2,
      plotWidth: 300,
    );
    expect(hidden, isEmpty);

    final visible = ReplayTradeOverlayLayout.visible(
      trades: [openBuy],
      viewport: viewport,
      scale: scale,
      candleCount: 5,
      plotWidth: 300,
    );
    expect(visible, hasLength(1));
    expect(visible.single.entryX, 275);
    expect(visible.single.endX, 295); // Last revealed bar, not the future.
    expect(visible.single.entryY, closeTo(170, .0001));
    expect(visible.single.stopY, closeTo(220, .0001));
    expect(visible.single.targetY, closeTo(80, .0001));
    expect(visible.single.exitY, isNull);
  });

  test('closed trade segments end on their actual exit, not chart edge', () {
    const closed = ReplayTrainingTrade(
      id: 2, side: ReplaySide.sell, entryIndex: 1,
      entryPrice: 110, quantity: 2,
      stopLoss: 115, takeProfit: 100,
      exitIndex: 3, exitPrice: 100, exitReason: ReplayExitReason.takeProfit,
    );
    final marks = ReplayTradeOverlayLayout.visible(
      trades: [closed],
      viewport: viewport,
      scale: scale,
      candleCount: 10,
      plotWidth: 300,
    );
    expect(marks, hasLength(1));
    expect(marks.single.endX, viewport.chartX(
      index: 3, candleCount: 10, plotWidth: 300));
    expect(marks.single.entryX, viewport.chartX(
      index: 1, candleCount: 10, plotWidth: 300));
    expect(marks.single.exitY, closeTo(200, .0001));
    expect(marks.single.stopY, closeTo(50, .0001));
    expect(marks.single.targetY, closeTo(200, .0001));
  });

  test('two practice orders do not share endpoints or level lines', () {
    const second = ReplayTrainingTrade(
      id: 3, side: ReplaySide.sell, entryIndex: 4,
      entryPrice: 109, quantity: 2,
      stopLoss: 114, takeProfit: 103,
    );
    final marks = ReplayTradeOverlayLayout.visible(
      trades: [openBuy, second],
      viewport: viewport,
      scale: scale,
      candleCount: 6,
      plotWidth: 300,
    );
    expect(marks, hasLength(2));
    expect(marks[0].trade.id, 1);
    expect(marks[1].trade.id, 3);
    expect(marks[0].entryX, isNot(marks[1].entryX));
    expect(marks[0].stopY, isNot(marks[1].stopY));
    expect(marks[0].targetY, isNot(marks[1].targetY));
  });

  test('invalid future exit never draws an exit marker', () {
    const invalidFutureExit = ReplayTrainingTrade(
      id: 4, side: ReplaySide.buy, entryIndex: 1,
      entryPrice: 100, quantity: 1, exitIndex: 8, exitPrice: 115,
      exitReason: ReplayExitReason.manual,
    );
    final marks = ReplayTradeOverlayLayout.visible(
      trades: [invalidFutureExit],
      viewport: viewport,
      scale: scale,
      candleCount: 4,
      plotWidth: 300,
    );
    expect(marks.single.exitY, isNull);
    expect(marks.single.endX, viewport.chartX(
      index: 3, candleCount: 4, plotWidth: 300));
  });

  test('offscreen trades and empty candle prefixes skip painting', () {
    expect(ReplayTradeOverlayLayout.visible(
      trades: [openBuy], viewport: viewport, scale: scale,
      candleCount: 0, plotWidth: 300), isEmpty);
    const ancientClosed = ReplayTrainingTrade(
      id: 9, side: ReplaySide.buy, entryIndex: 2, entryPrice: 103,
      quantity: 1, exitIndex: 3, exitPrice: 105,
      exitReason: ReplayExitReason.manual,
    );
    expect(ReplayTradeOverlayLayout.visible(
      trades: [ancientClosed],
      viewport: const ChartViewport(barWidth: 10, scrollBars: 500),
      scale: scale,
      candleCount: 1000, plotWidth: 300), isEmpty);
  });

  test('visible SL/TP dashes skip millions of hidden pixels in O(viewport)',
      () {
    final dashes = ReplayTradeOverlayLayout.visibleDashSegments(
        x1: -2000000, x2: 295, plotWidth: 300).toList();
    expect(dashes.length, lessThanOrEqualTo(27));
    expect(dashes, isNotEmpty);
    expect(dashes.every((dash) =>
        dash.$1 >= 0 && dash.$2 <= 300 && dash.$2 > dash.$1), isTrue);
    // Retain the original dash period even when x1 is far left.
    for (final (start, end) in dashes) {
      expect(end - start, lessThanOrEqualTo(7));
      final phase = ((start + 2000000) % 12);
      expect(phase, lessThanOrEqualTo(7));
    }
    expect(ReplayTradeOverlayLayout.visibleStroke(
        x1: -2000000, x2: 295, plotWidth: 300), (0.0, 295.0));
    expect(ReplayTradeOverlayLayout.visibleStroke(
        x1: -2000000, x2: -10, plotWidth: 300), isNull);
    expect(ReplayTradeOverlayLayout.visibleStroke(
        x1: 400, x2: 600, plotWidth: 300), isNull);
  });

  test('dash phase stays anchored while panning and zooming', () {
    final segments = ReplayTradeOverlayLayout.visibleDashSegments(
        x1: 10, x2: 55, plotWidth: 300).toList();
    expect(segments, [(10.0, 17.0), (22.0, 29.0),
      (34.0, 41.0), (46.0, 53.0)]);
    final clipped = ReplayTradeOverlayLayout.visibleDashSegments(
        x1: -2, x2: 28, plotWidth: 30).toList();
    expect(clipped, [(0.0, 5.0), (10.0, 17.0),
      (22.0, 28.0)]);
    expect(ReplayTradeOverlayLayout.visibleDashSegments(
        x1: -100, x2: -20, plotWidth: 300), isEmpty);
    expect(ReplayTradeOverlayLayout.visibleDashSegments(
        x1: 10, x2: 300, plotWidth: double.nan), isEmpty);
    expect(ReplayTradeOverlayLayout.visibleStroke(
        x1: double.infinity, x2: 2, plotWidth: 300), isNull);
  });

  testWidgets('overlay safely paints a 200k-bar historical practice position',
      (tester) async {
    const longOpen = ReplayTrainingTrade(
      id: 77, side: ReplaySide.buy, entryIndex: 0,
      entryPrice: 103, quantity: 1,
      stopLoss: 98, takeProfit: 112,
    );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(
        width: 320, height: 240,
        child: CustomPaint(
          key: const Key('long-practice-position'),
          painter: ReplayTradeOverlayPainter(
            trades: const [longOpen],
            viewport: const ChartViewport(barWidth: 10),
            scale: const ChartPriceScale(90, 120, 216),
            candleCount: 200000, plotWidth: 259,
          ),
        ),
      )),
    ));
    expect(find.byKey(const Key('long-practice-position')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('isolated overlay paints without altering gestures or source',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(
        width: 320,
        height: 240,
        child: CustomPaint(
          key: const Key('practice-overlay-only'),
          painter: ReplayTradeOverlayPainter(
            trades: const [openBuy],
            viewport: viewport,
            scale: const ChartPriceScale(90, 120, 216),
            candleCount: 5,
            plotWidth: 259,
          ),
        ),
      )),
    ));
    expect(find.byKey(const Key('practice-overlay-only')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
