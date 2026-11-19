import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

/// A moving chart may repaint every frame, but must not rebuild the header,
/// account controls and tab layout on every pointer sample.
/// No broker data or fabricated market candles are needed to test this path.
void main() {
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
