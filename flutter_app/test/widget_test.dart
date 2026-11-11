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
    expect(find.byKey(const Key('chart-reference-header')), findsOneWidget);
    expect(find.byKey(const Key('chart-reference-toolbar')), findsOneWidget);
    expect(find.textContaining('لا توجد أسعار موثقة'), findsOneWidget);
    expect(find.text('1 دق'), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.textContaining('اربط حساب cTrader من شاشة الحساب'), findsOneWidget);
    expect(find.text('معاينة'), findsNothing);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('Replay cannot start without verified broker candles', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('analysis hub opens above chart and routes to candle types',
      (tester) async {
    await openAtPhoneSize(tester);
    final chart = find.byKey(const Key('chart-gesture-area'));
    expect(chart, findsOneWidget);
    await tester.tap(find.byTooltip('محور التحليل'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analysis-hub-sheet')), findsOneWidget);
    expect(find.byKey(const Key('analysis-action-saveLayout')), findsOneWidget);
    expect(chart, findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('analysis-action-chartType')));
    await tester.tap(find.byKey(const Key('analysis-action-chartType')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-type-bottom-sheet')), findsOneWidget);
    expect(chart, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(chart, findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
  });

  testWidgets('analysis hub indicator catalog and Replay stay on chart',
      (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('محور التحليل'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('analysis-action-indicators')));
    await tester.tap(find.byKey(const Key('analysis-action-indicators')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('analysis-sma12-toggle')), findsOneWidget);
    await tester.tap(find.byKey(const Key('analysis-sma12-toggle')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('محور التحليل'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('analysis-action-replay')));
    await tester.tap(find.byKey(const Key('analysis-action-replay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
  });

  testWidgets('Heikin-Ashi and Range never show unlinked synthetic candles',
      (tester) async {
    var requests = 0;
    final controller = MarketController(api: MarketApi(client: MockClient((_) async {
      requests++;
      throw StateError('A cTrader market request must not be sent before authorization');
    })));
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TradeLabApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    await tester.tap(find.byTooltip('نوع الشموع'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('chart-kind-heikinAshi')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const Key('chart-type-grid')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('chart-kind-heikinAshi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);

    await tester.tap(find.byTooltip('نوع الشموع'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('chart-kind-range')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const Key('chart-type-grid')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('chart-kind-range')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.textContaining('تيكات تجريبية'), findsNothing);
    expect(find.textContaining('تيكات BID الحقيقية'), findsOneWidget);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('chart-kind-range')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const Key('chart-type-grid')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('chart-kind-range')));
    await tester.pumpAndSettle();
    expect(find.text('إعدادات شموع المدى'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    await tester.tap(find.text('250'));
    await tester.pumpAndSettle();
    expect(find.text('مدى 250'), findsWidgets);
  });

  testWidgets('drawing picker offers price line, trend line, and Fibonacci',
      (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('أدوات الرسم'));
    await tester.pumpAndSettle();
    expect(find.text('رسومات'), findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-trendLine')), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawing-category-gann')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-tool-fibonacciRetracement')),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('drawing-category-trend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawing-category-trend')));
    await tester.pumpAndSettle();
    expect(find.text('خط اتجاه'), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawing-tool-trendLine')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('ray selection does not seed prices before cTrader is linked',
      (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('أدوات الرسم'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-tool-ray')), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawing-tool-ray')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
  });

  testWidgets('sell-position shortcuts never seed an empty cTrader feed',
      (tester) async {
    await openAtPhoneSize(tester);
    // Price-specific shortcuts appear only with verified candles, unlike the
    // reference's nine general commands. They must not create sample prices.
    expect(find.byKey(const Key('drawing-rail-short')), findsNothing);
    await tester.tap(find.byTooltip('أدوات الرسم'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('drawing-category-tools')));
    await tester.tap(find.byKey(const Key('drawing-category-tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-general-eraser')), findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-shortPosition')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // With no authorized cTrader candles, the screenshot's sample prices
    // must never appear as an invented position or market feed.
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('short-position-placement-hint')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('price rectangle remains unavailable without real XAUUSD candles',
      (tester) async {
    await openAtPhoneSize(tester);
    expect(find.byKey(const Key('drawing-rail-rectangle')), findsNothing);
    await tester.tap(find.byTooltip('أدوات الرسم'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('drawing-category-tools')));
    await tester.tap(find.byKey(const Key('drawing-category-tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-general-ruler')), findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-priceRectangle')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('price-rectangle-placement-hint')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('PROMPT 07 general zoom preserves empty real-feed state',
      (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('أدوات الرسم'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('drawing-category-tools')));
    await tester.tap(find.byKey(const Key('drawing-category-tools')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-general-zoomIn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('drawing-general-action-zoomIn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('PROMPT 07 deleting no drawings cannot mutate market data',
      (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('أدوات الرسم'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('drawing-category-tools')));
    await tester.tap(find.byKey(const Key('drawing-category-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawing-general-action-deleteDrawings')));
    await tester.pump();
    expect(find.text('لا توجد رسومات لحذفها'), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
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
    expect(tester.takeException(), isNull, reason: 'initial chart layout');
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'symbol picker layout');
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Binance chart layout');
    expect(find.text('شموع Binance'), findsOneWidget);
    expect(find.textContaining('شموع Binance ·'), findsOneWidget);
    expect(find.textContaining('جارِ تحميل شموع'), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق Replay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analysis hub retains Binance candles and starts Replay without refetch',
      (tester) async {
    var historyRequests = 0;
    final client = MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      historyRequests++;
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
    expect(historyRequests, 1);
    expect(find.text('شموع Binance'), findsOneWidget);
    final chart = find.byKey(const Key('chart-gesture-area'));
    expect(chart, findsOneWidget);

    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byTooltip('محور التحليل'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analysis-hub-sheet')), findsOneWidget);
      expect(chart, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(chart, findsOneWidget);
      expect(historyRequests, 1);
    }

    await tester.tap(find.byTooltip('محور التحليل'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('analysis-action-replay')));
    await tester.tap(find.byKey(const Key('analysis-action-replay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(chart, findsOneWidget);
    expect(historyRequests, 1);
    await tester.tap(find.byTooltip('إغلاق Replay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(historyRequests, 1);
    expect(tester.takeException(), isNull);
  });
}
