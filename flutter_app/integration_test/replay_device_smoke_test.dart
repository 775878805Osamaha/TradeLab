import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

/// Android-only smoke tests. They exercise real Flutter/sqflite Android
/// plugins but never use broker secrets or make a live market data request.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unlinked cTrader chart does not invent prices or start Replay',
      (tester) async {
    await tester.pumpWidget(const TradeLabApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);

    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-practice-order')), findsNothing);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android: Binance chart supports isolated Replay practice',
      (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      requests++;
      // Authentically shaped Binance closed candles, but deliberately fixed
      // test values. The test never claims these are live broker quotes.
      return http.Response(jsonEncode([
        [1700000000000, '35000', '35200', '34700', '35100', '1', 1700000899999],
        [1700000900000, '35100', '35300', '35000', '35250', '1', 1700001799999],
      ]), 200);
    });
    final controller = MarketController(api: MarketApi(client: client));
    addTearDown(controller.dispose);

    await tester.pumpWidget(TradeLabApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();

    expect(requests, greaterThan(0));
    expect(find.text('شموع Binance'), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    final chart = find.byKey(const Key('chart-gesture-area'));
    expect(chart, findsOneWidget);

    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('replay-speed-picker')), findsOneWidget);
    expect(find.byKey(const Key('replay-practice-order')), findsOneWidget);

    await tester.tap(find.byKey(const Key('replay-practice-order')));
    await tester.pumpAndSettle();
    expect(find.text('صفقة تدريب داخل Replay'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('صفقاتي (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-practice-list')));
    await tester.pumpAndSettle();
    expect(find.text('صفقات التدريب التاريخية'), findsOneWidget);
    expect(find.textContaining('مفتوحة'), findsWidgets);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();

    // The Android chart and gesture surface remain mounted throughout
    // Replay. This checks event handling, not frame-time performance.
    expect(chart, findsOneWidget);
    await tester.drag(chart, const Offset(36, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
