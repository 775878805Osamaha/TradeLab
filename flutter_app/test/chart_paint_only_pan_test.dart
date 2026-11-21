import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/main.dart';

/// A moving chart may repaint every frame, but must not rebuild the header,
/// account controls and tab layout on every pointer sample.
/// No broker data or fabricated market candles are needed to test this path.
/// Offline quote publisher: supplies source-shaped, timestamp-validated
/// prices but makes NO broker/market HTTP calls. It records when the
/// retained chart painter reads source quotes after a paint notification.
class _QuotePaintController extends MarketController {
  _QuotePaintController(MarketApi api) : super(api: api);

  MarketQuote? _quote;
  int reads = 0;

  @override
  MarketQuote? recentQuoteFor(TradeSymbol symbol) {
    reads++;
    final source = _quote;
    if (source == null || source.symbol != symbol.code ||
        source.source != symbol.source) return null;
    try {
      source.assertFresh(nowMs: DateTime.now().toUtc().millisecondsSinceEpoch);
      return source;
    } on MarketDataException {
      return null;
    }
  }

  void publishQuote(MarketQuote quote) {
    _quote = quote;
    notifyListeners();
  }
}

void main() {
  // Flutter's scale recognizer starts after movement crosses touch slop.
  // Source-anchored drawing hits must resolve at FIRST contact instead of
  // the finger's displaced position (which could be 24dp away already).
  for (final width in <double>[320, 390]) {
    for (final kind in <String>['horizontal', 'trendLine']) {
      testWidgets('first finger contact owns existing $kind guide after '
          '24dp scale slop at ${width}dp', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final client = MockClient((request) async {
          if (request.url.path == '/api/v3/klines') {
            return http.Response(jsonEncode(List.generate(120, (i) {
              final ms = 1700000000000 + i * 900000;
              return [ms, '${35000 + i}', '${35100 + i}',
                '${34900 + i}', '${35050 + i}', '1', ms + 899999];
            })), 200);
          }
          return http.Response('{"error":"offline"}', 503);
        });
        final market = MarketController(api: MarketApi(client: client));
        addTearDown(market.dispose);
        await tester.pumpWidget(MaterialApp(home: Scaffold(
          body: ChartScreen(
            controller: market, requestedSymbolCode: 'BTCUSDT'),
        )));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chart-source-empty')), findsNothing);
        final rect = tester.getRect(
            find.byKey(const Key('chart-gesture-area')));
        final contact = Offset(
            rect.left + (rect.width - 61) * .55, rect.center.dy);
        Future<void> chooseDrawing() async {
          await tester.tap(
              find.byKey(const Key('drawing-rail-open-catalog')));
          await tester.pumpAndSettle();
          final tool = find.byKey(Key('drawing-tool-$kind'));
          await tester.ensureVisible(tool);
          await tester.tap(tool);
          await tester.pumpAndSettle();
        }
        await chooseDrawing();
        final dynamic state = tester.state(find.byType(ChartScreen));
        if (kind == 'horizontal') {
          await tester.tapAt(contact);
        } else {
          await tester.tapAt(contact - const Offset(38, 28));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tapAt(contact + const Offset(38, 28));
        }
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final created = state.debugGuideDragSelection;
        expect(kind == 'horizontal' ? created.levels : created.patterns, 1,
            reason: 'The actual market-anchored guide must exist first');
        await chooseDrawing();

        final finger = await tester.startGesture(contact);
        await finger.moveBy(const Offset(0, -24));
        await tester.pump();
        final grabbing = state.debugGuideDragSelection;
        expect(kind == 'horizontal'
            ? grabbing.draggingLine : grabbing.draggingPattern, isTrue,
            reason: 'Touch ownership comes from original contact, not '
                'the position after 24dp of gesture slop');
        final header = find.byKey(const Key('chart-reference-header'));
        final retainedHeader = tester.widget(header);
        final firstPrice = kind == 'horizontal'
            ? grabbing.levelValue : grabbing.patternValue?.start.price;
        for (var step = 0; step < 5; step++) {
          await finger.moveBy(const Offset(0, -7));
          await tester.pump();
          expect(identical(retainedHeader, tester.widget(header)), isTrue,
              reason: 'Each guide touch sample repaints the retained canvas, '
                  'not the 320/390dp chart toolbar');
          final active = state.debugGuideDragSelection;
          expect(kind == 'horizontal'
              ? active.draggingLine : active.draggingPattern, isTrue);
          expect(tester.takeException(), isNull);
        }
        final moved = state.debugGuideDragSelection;
        final finalPrice = kind == 'horizontal'
            ? moved.levelValue : moved.patternValue?.start.price;
        expect(firstPrice, isNotNull);
        expect(finalPrice, isNotNull);
        expect(finalPrice, isNot(firstPrice),
            reason: 'The source-anchored guide itself must move, not '
                'just the pointer or header state');
        await finger.up();
        await tester.pumpAndSettle();
        final completed = state.debugGuideDragSelection;
        expect(completed.draggingLine, isFalse);
        expect(completed.draggingPattern, isFalse);
        expect(kind == 'horizontal' ? completed.levels : completed.patterns, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('ordinary chart pan repaints without rebuilding header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 770));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final market = MarketController();
    addTearDown(market.dispose);

    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();
    final chart = find.byKey(const Key('chart-gesture-area'));
    final header = find.byKey(const Key('chart-reference-header'));
    expect(chart, findsOneWidget);
    expect(header, findsOneWidget);

    // The initial touch sets a one-time UI flag. Subsequent movement must
    // stay on the CustomPainter repaint fast path.
    await tester.drag(chart, const Offset(-70, 0));
    await tester.pumpAndSettle();
    final previousHeaderWidget = tester.widget(header);
    await tester.drag(chart, const Offset(-80, 0));
    // Drain GestureDetector's pending double-tap recognizer timeout before
    // the test binding checks for leaked timers after widget disposal.
    await tester.pump(const Duration(milliseconds: 400));

    expect(identical(previousHeaderWidget, tester.widget(header)), isTrue,
        reason: 'Gesture samples should repaint candles, not rebuild controls');
    expect(tester.takeException(), isNull);
  });

  testWidgets('streaming price changes repaint chart, not entire controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient((request) async {
      if (request.url.path == '/api/v3/klines') {
        return http.Response(jsonEncode(List.generate(120, (i) {
          final ms = 1700000000000 + i * 900000;
          return [ms, '${35000 + i}', '${35100 + i}',
            '${34900 + i}', '${35050 + i}', '1', ms + 899999];
        })), 200);
      }
      return http.Response('{"error":"offline"}', 503);
    });
    final market = _QuotePaintController(MarketApi(client: client));
    addTearDown(market.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ChartScreen(controller: market, requestedSymbolCode: 'BTCUSDT'),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    final header = find.byKey(const Key('chart-reference-header'));
    final original = tester.widget(header);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final sameMinute = now ~/ 60000 * 60000;
    // Repeated real-structure source BID/ASK revisions in one minute must
    // update the painter, not rebuild TradeLab's expensive toolbar.
    for (var i = 0; i < 20; i++) {
      market.publishQuote(MarketQuote(
        symbol: 'BTCUSDT', source: TradeSource.binance,
        bid: 35100 + i / 10, ask: 35100.5 + i / 10,
        timestampMs: sameMinute,
      ));
      final readsOnNotice = market.reads;
      await tester.pump();
      expect(market.reads, greaterThan(readsOnNotice),
        reason: 'Retained CustomPainter must read fresh source at paint time');
      expect(identical(original, tester.widget(header)), isTrue,
        reason: 'BID/ASK changes should not rebuild header on each source tick');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('manual ruler range resets on Replay entry and exit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient((request) async {
      if (request.url.path == '/api/v3/klines') {
        return http.Response(jsonEncode(List.generate(120, (i) {
          final ms = 1700000000000 + i * 900000;
          return [ms, '${35000 + i}', '${35100 + i}',
            '${34900 + i}', '${35050 + i}', '1', ms + 899999];
        })), 200);
      }
      return http.Response('{"error":"offline"}', 503);
    });
    final market = MarketController(api: MarketApi(client: client));
    addTearDown(market.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ChartScreen(controller: market, requestedSymbolCode: 'BTCUSDT'),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    final rect = tester.getRect(find.byKey(const Key('chart-gesture-area')));
    Future<void> manualZoom() async {
      await tester.dragFrom(
          Offset(rect.right - 22, rect.center.dy), const Offset(0, -85));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-price-axis-auto')), findsOneWidget);
    }

    await manualZoom();
    final start = find.byTooltip('تشغيل Replay داخل الشارت');
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-start-overlay')), findsOneWidget);
    expect(find.byKey(const Key('chart-price-axis-auto')), findsNothing,
      reason: 'Old live zoom must not hide selected historical candles');
    await tester.tap(find.byKey(const Key('replay-confirm-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);

    await manualZoom();
    await tester.tap(find.byKey(const Key('replay-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-price-axis-auto')), findsNothing,
      reason: 'Old Replay zoom must not hide live market source');
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 390]) {
    testWidgets('bottom time axis zooms actual candles without panning chart '
        'or rebuilding header every frame at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          return http.Response(jsonEncode(List.generate(120, (i) {
            final ms = 1700000000000 + i * 900000;
            return [ms, '${35000 + i}', '${35100 + i}',
              '${34900 + i}', '${35050 + i}', '1', ms + 899999];
          })), 200);
        }
        return http.Response('{"error":"offline"}', 503);
      });
      final market = MarketController(api: MarketApi(client: client));
      addTearDown(market.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ChartScreen(controller: market, requestedSymbolCode: 'BTCUSDT'),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-source-empty')), findsNothing);
      final chart = find.byKey(const Key('chart-gesture-area'));
      final header = find.byKey(const Key('chart-reference-header'));
      final rect = tester.getRect(chart);
      final plotWidth = rect.width - 61;
      ChartViewport currentViewport() {
        final painter = tester.widget<CustomPaint>(find.descendant(
            of: chart, matching: find.byType(CustomPaint)).first).painter;
        final dynamic livePainter = painter;
        return livePainter.viewport as ChartViewport;
      }
      final initial = currentViewport();
      final axisTouch = Offset(
          rect.left + plotWidth / 2, rect.bottom - 10);
      final gesture = await tester.startGesture(axisTouch);
      await gesture.moveBy(const Offset(44, 0));
      await tester.pump();
      final afterFirst = currentViewport();
      expect(afterFirst.barWidth, greaterThan(initial.barWidth),
        reason: 'Rightward time-ruler drag magnifies the time scale');
      final headerDuringDrag = tester.widget(header);
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      final afterSecond = currentViewport();
      expect(afterSecond.barWidth, greaterThan(afterFirst.barWidth));
      expect(identical(headerDuringDrag, tester.widget(header)), isTrue,
        reason: 'Time-axis updates use chart painter, not full toolbar build');
      expect(find.byKey(const Key('chart-price-axis-auto')), findsNothing,
        reason: 'Time ruler never switches to manual vertical price scale');
      await gesture.up();
      await tester.pumpAndSettle();

      final widthAfterTimeZoom = currentViewport().barWidth;
      await tester.dragFrom(
          Offset(rect.left + plotWidth / 2, rect.center.dy),
          const Offset(-45, 0));
      await tester.pumpAndSettle();
      expect(currentViewport().barWidth, closeTo(widthAfterTimeZoom, 1e-9),
        reason: 'One-finger drag on the plot pans, not zooms time');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[320, 390]) {
    testWidgets('crosshair reveals verified OHLC without rebuilding chart '
        'controls at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          final rows = List.generate(120, (i) {
            final ts = 1700000000000 + i * 900000;
            return [ts, '${35000 + i}', '${35100 + i}',
              '${34900 + i}', '${35050 + i}', '1', ts + 899999];
          });
          return http.Response(jsonEncode(rows), 200);
        }
        return http.Response('{"error":"offline"}', 503);
      });
      final market = MarketController(api: MarketApi(client: client));
      addTearDown(market.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ChartScreen(controller: market, requestedSymbolCode: 'BTCUSDT'),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-source-empty')), findsNothing);
      final chart = find.byKey(const Key('chart-gesture-area'));
      final rect = tester.getRect(chart);
      final candleX = rect.right - 61 - 45;
      final touch = await tester.startGesture(
          Offset(candleX, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump();
      expect(find.byKey(const Key('chart-crosshair-ohlc-inspector')),
          findsOneWidget);
      expect(find.text('O 35119.00'), findsOneWidget);
      expect(find.text('H 35219.00'), findsOneWidget);
      expect(find.text('L 35019.00'), findsOneWidget);
      expect(find.text('C 35169.00'), findsOneWidget);
      final header = find.byKey(const Key('chart-reference-header'));
      final originalHeader = tester.widget(header);
      await touch.moveTo(Offset(candleX - 20, rect.center.dy));
      await tester.pump();
      expect(find.text('O 35117.00'), findsOneWidget);
      expect(find.text('C 35167.00'), findsOneWidget);
      expect(identical(originalHeader, tester.widget(header)), isTrue,
        reason: 'OHLC moves with painter notifier, not full chart rebuild');
      await touch.up();
      await tester.pumpAndSettle();
      // TradingView Mobile retains tracking/OHLC after the finger lifts:
      // a separate single tap is required to dismiss the inspection.
      expect(find.byKey(const Key('chart-crosshair-ohlc-inspector')),
          findsOneWidget);
      await tester.tapAt(Offset(candleX - 40, rect.center.dy));
      // The chart also owns a double-tap recognizer. Let its 40ms
      // recognizer countdown finish in fake async before this widget test
      // ends; otherwise Flutter correctly flags a pending framework timer.
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-crosshair-ohlc-inspector')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[320, 390]) {
    testWidgets('TradingView-style right price ruler drag shows AUTO at '
        '${width}dp without changing time-axis gesture mode', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          final rows = List.generate(120, (i) {
            final ts = 1700000000000 + i * 900000;
            return [ts, '${35000 + i}', '${35100 + i}',
              '${34900 + i}', '${35050 + i}', '1', ts + 899999];
          });
          return http.Response(jsonEncode(rows), 200);
        }
        return http.Response('{"error":"offline"}', 503);
      });
      final market = MarketController(api: MarketApi(client: client));
      addTearDown(market.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ChartScreen(controller: market, requestedSymbolCode: 'BTCUSDT'),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-source-empty')), findsNothing,
          reason: 'Test chart must use real-structure mock Binance OHLC');
      final gesture = find.byKey(const Key('chart-gesture-area'));
      expect(gesture, findsOneWidget);
      expect(find.byKey(const Key('chart-price-axis-auto')), findsNothing);
      final rect = tester.getRect(gesture);
      final rightScale = Offset(rect.right - 22, rect.center.dy);

      // A vertical drag inside the price-axis 61dp strip must change only
      // the price coordinates and offer an explicit reset.
      await tester.dragFrom(rightScale, const Offset(0, -88));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-price-axis-auto')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('chart-price-axis-auto')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-price-axis-auto')), findsNothing);

      // A normal plot swipe still pans horizontally, not prices vertically.
      final x = rect.left + (rect.width - 61) / 2;
      await tester.dragFrom(Offset(x, rect.center.dy),
          const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-price-axis-auto')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

}
