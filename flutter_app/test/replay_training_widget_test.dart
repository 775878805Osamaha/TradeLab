import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('verified Binance candles enable Replay training in same chart',
      (tester) async {
    // Reuse the fixed, known-good Binance fixture from widget_test.dart,
    // which already proves the real chart and Replay entry point work.
    final client = MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      return http.Response(jsonEncode([
        [1700000000000, '35000', '35200', '34700', '35100', '1', 1700000899999],
        [1700000900000, '35100', '35300', '35000', '35250', '1', 1700001799999],
      ]), 200);
    });
    final controller = MarketController(api: MarketApi(client: client));
    addTearDown(controller.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TradeLabApp(controller: controller));
    // This matches the already-passing Binance chart widget test. Keep
    // SQLite FFI inactive until the real market-data chart has initialized.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('symbol-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();
    // Stop waiting once verified broker bars have actually been rendered.
    // A bounded readiness check produces a specific failure instead of
    // ever waiting for unrelated refresh animations to settle.
    for (var attempt = 0;
        attempt < 40 &&
            find.byKey(const Key('chart-source-empty')).evaluate().isNotEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('شموع Binance'), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsNothing,
        reason: 'Expected verified Binance candles before entering Replay');
    // Archive persistence is a separate concern. Activate FFI only after
    // the chart has finished source loading and is safe to enter Replay.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    // Replay first lets the user choose a verified source candle: no
    // historical future data is hidden or training session opened until OK.
    expect(find.byKey(const Key('replay-start-overlay')), findsOneWidget);
    expect(find.byKey(const Key('replay-start-scissors')), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    await tester.tap(find.byKey(const Key('replay-confirm-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-start-overlay')), findsNothing);
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('replay-speed-picker')), findsOneWidget);
    expect(find.byKey(const Key('replay-practice-order')), findsOneWidget);

    await tester.tap(find.byKey(const Key('replay-practice-order')));
    await tester.pumpAndSettle();
    expect(find.text('صفقة تدريب داخل Replay'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('صفقاتي (1)'), findsOneWidget);
    expect(find.byKey(const Key('replay-practice-levels-overlay')),
        findsOneWidget,
        reason: 'An entered practice trade should have chart markers');
    await tester.tap(find.byKey(const Key('replay-practice-list')));
    await tester.pumpAndSettle();
    expect(find.text('صفقات التدريب التاريخية'), findsOneWidget);
    expect(find.textContaining('مفتوحة'), findsWidgets);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
