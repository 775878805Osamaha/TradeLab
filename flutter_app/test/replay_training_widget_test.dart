import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

// The chart has ongoing timers and animated quote/update surfaces. A bounded
// number of test frames is deterministic and checks real visible readiness
// instead of waiting for all scheduled frames to stop forever.
Future<void> pumpUiFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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
    // The app has an ongoing live-data refresh lifecycle; waiting for every
    // scheduled frame can hang indefinitely. Let the initial chart build
    // complete, then assert the specific UI readiness condition instead.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('symbol-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await pumpUiFrames(tester);
    await tester.tap(find.text('BTCUSDT').last);
    await pumpUiFrames(tester);
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
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await pumpUiFrames(tester);
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('replay-speed-picker')), findsOneWidget);
    expect(find.byKey(const Key('replay-practice-order')), findsOneWidget);

    await tester.tap(find.byKey(const Key('replay-practice-order')));
    await pumpUiFrames(tester);
    expect(find.text('صفقة تدريب داخل Replay'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await pumpUiFrames(tester);

    expect(find.textContaining('صفقاتي (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-practice-list')));
    await pumpUiFrames(tester);
    expect(find.text('صفقات التدريب التاريخية'), findsOneWidget);
    expect(find.textContaining('مفتوحة'), findsWidgets);
    await tester.tap(find.text('إغلاق').last);
    await pumpUiFrames(tester);

    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
