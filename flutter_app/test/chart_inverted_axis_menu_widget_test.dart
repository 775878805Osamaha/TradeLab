import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('long-press price scale offers invert and restores standard '
        'without new history at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          requests++;
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
        body: ChartScreen(controller: market,
            requestedSymbolCode: 'BTCUSDT'),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-source-empty')), findsNothing);
      final chart = tester.getRect(
          find.byKey(const Key('chart-gesture-area')));
      final axisPoint = Offset(chart.right - 22, chart.center.dy);
      final requestBaseline = requests;
      expect(requestBaseline, greaterThan(0));

      await tester.longPressAt(axisPoint);
      await tester.pumpAndSettle();
      final invert = find.byKey(const Key('chart-price-axis-menu-invert'));
      expect(invert, findsOneWidget);
      expect(find.text('عكس مقياس السعر'), findsOneWidget);
      await tester.tap(invert);
      await tester.pumpAndSettle();
      expect(requests, requestBaseline,
          reason: 'Invert must not requery or mutate broker OHLC');

      await tester.longPressAt(axisPoint);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-price-axis-menu-invert')),
          findsOneWidget);
      expect(find.text('إلغاء عكس مقياس السعر'), findsOneWidget);
      await tester.tap(find.byKey(
          const Key('chart-price-axis-menu-invert')));
      await tester.pumpAndSettle();
      expect(requests, requestBaseline);
      expect(tester.takeException(), isNull);
    });
  }
}
