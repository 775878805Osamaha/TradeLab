import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Real Flutter navigation and source-shaped offline response. The fixture
/// never appears in production trading or replay market data.
void main() {
  for (final width in <double>[320, 390]) {
    for (final mode in <String>['نسبة مئوية', 'مؤشر 100']) {
      testWidgets('right-axis menu applies $mode to existing source'
          ' without a history refresh at ${width}dp', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var requests = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/api/v3/klines') {
            requests++;
            return http.Response(jsonEncode(List.generate(120, (i) {
              final ms = 1700000000000 + i * 900000;
              final price = 35000.0 + i * 10;
              return [ms, '$price', '${price + 30}',
                  '${price - 20}', '${price + 5}', '1',
                  ms + 899999];
            })), 200);
          }
          return http.Response('{"error":"offline"}', 503);
        });
        final controller = MarketController(api: MarketApi(client: client));
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(home: Scaffold(
          body: ChartScreen(controller: controller,
              requestedSymbolCode: 'BTCUSDT'),
        )));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chart-source-empty')), findsNothing);
        final baseline = requests;
        expect(baseline, greaterThan(0));
        final rect = tester.getRect(
            find.byKey(const Key('chart-gesture-area')));
        await tester.longPressAt(Offset(rect.right - 22, rect.center.dy));
        await tester.pumpAndSettle();
        final settings = find.byKey(
            const Key('chart-price-axis-menu-settings'));
        expect(settings, findsOneWidget);
        await tester.tap(settings);
        await tester.pumpAndSettle();

        final dropdown = find.byKey(const Key('scale-mode'));
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(find.text(mode), findsOneWidget);
        await tester.tap(find.text(mode).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('scale-apply')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
        expect(find.byKey(const Key('chart-source-empty')), findsNothing);
        expect(requests, baseline,
            reason: 'Relative labels use already loaded authenticated'
                ' source bars, not a new broker or future Replay call');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
