import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

void main() {
  Future<void> openAtPhoneSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const TradeLabApp());
    await tester.pumpAndSettle();
  }

  testWidgets('opens approved RTL chart in analysis mode', (tester) async {
    await openAtPhoneSize(tester);
    expect(find.text('XAUUSD'), findsWidgets);
    expect(find.textContaining('معاينة تصميم Flutter'), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('Replay controls stay inside the chart', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق Replay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
  });

  testWidgets('chart accepts one-finger drag and returns to latest', (tester) async {
    await openAtPhoneSize(tester);
    final chart = find.byKey(const Key('chart-gesture-area'));
    await tester.drag(chart, const Offset(-130, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('العودة إلى أحدث شمعة'));
    await tester.tap(find.byTooltip('العودة إلى أحدث شمعة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact chart remains readable on narrow screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const TradeLabApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('Range candles selector has explicit settings', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('نوع الشموع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شموع المدى').last);
    await tester.pumpAndSettle();
    expect(find.text('إعدادات شموع المدى'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    await tester.tap(find.text('250'));
    await tester.pumpAndSettle();
    expect(find.text('مدى 250'), findsWidgets);
  });

  testWidgets('navigation retains results and account screens', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.text('النتائج').last);
    await tester.pumpAndSettle();
    expect(find.text('النتائج والتحليلات'), findsOneWidget);
    expect(find.text('صافي الربح'), findsOneWidget);
    await tester.tap(find.text('الحساب').last);
    await tester.pumpAndSettle();
    expect(find.text('الحساب والإعدادات'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('dark-mode-switch')),
        180, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dark-mode-switch')), findsOneWidget);
  });

  testWidgets('switching to Binance loads verified candles, not design fixtures', (tester) async {
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();
    expect(find.text('بيانات فعلية'), findsOneWidget);
    expect(find.textContaining('جارِ تحميل شموع'), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
