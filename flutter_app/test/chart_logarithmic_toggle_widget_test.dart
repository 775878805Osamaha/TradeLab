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
    testWidgets('L price-axis button changes real chart display and'
        ' preserves source history at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requests = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v3/klines') {
          requests++;
          return http.Response(jsonEncode(List.generate(120, (i) {
            final ms = 1700000000000 + i * 900000;
            final price = 35000 + i * 100;
            return [ms, '$price', '${price + 300}',
                '${price - 200}', '${price + 50}', '1', ms + 899999];
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
      expect(requests, greaterThan(0));
      final rect = tester.getRect(find.byKey(const Key('chart-gesture-area')));
      await tester.dragFrom(
          Offset(rect.left + (rect.width - 61) / 2, rect.center.dy),
          const Offset(-20, 0));
      await tester.pumpAndSettle();

      final logButton = find.byKey(const Key('chart-price-axis-log'));
      expect(logButton, findsOneWidget);
      expect(find.descendant(of: logButton, matching: find.text('L')),
          findsOneWidget);
      final requestsBefore = requests;
      await tester.tap(logButton);
      await tester.pumpAndSettle();
      expect(find.descendant(of: logButton, matching: find.text('LOG')),
          findsOneWidget);
      expect(requests, requestsBefore,
          reason: 'LOG uses the already verified OHLC snapshot, never'
              ' triggers a new broker request or leaks Replay future');

      await tester.tap(logButton);
      await tester.pumpAndSettle();
      expect(find.descendant(of: logButton, matching: find.text('L')),
          findsOneWidget);
      expect(requests, requestsBefore);
      expect(tester.takeException(), isNull);
    });
  }
}
