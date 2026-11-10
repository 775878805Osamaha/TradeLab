import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

void main() {
  test('only crossing the Range boundary requires new history', () {
    expect(ChartMode.candles.requiresHistoryReload(ChartMode.heikinAshi),
        isFalse);
    expect(ChartMode.heikinAshi.requiresHistoryReload(ChartMode.candles),
        isFalse);
    expect(ChartMode.candles.requiresHistoryReload(ChartMode.candles),
        isFalse);
    expect(ChartMode.candles.requiresHistoryReload(ChartMode.range), isTrue);
    expect(ChartMode.range.requiresHistoryReload(ChartMode.heikinAshi), isTrue);
    expect(ChartMode.range.requiresHistoryReload(ChartMode.range), isFalse);
  });

  testWidgets('switching time-candle styles reuses broker history',
      (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      final rows = List.generate(120, (i) {
        final time = 1700000000000 + i * 900000;
        return [time, '35000', '35200', '34700', '35100', '1', time + 899999];
      });
      return http.Response(jsonEncode(rows), 200);
    });
    final controller = MarketController(api: MarketApi(client: client));
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(TradeLabApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);

    // The chart already has its real Binance page. Presentation changes
    // should not trigger another historical request or a loading screen.
    await tester.drag(find.byKey(const Key('chart-gesture-area')),
        const Offset(140, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نوع الشموع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('هيكن آشي').last);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.textContaining('جارِ تحميل شموع'), findsNothing);

    await tester.tap(find.byTooltip('نوع الشموع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الشموع اليابانية').last);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
}
