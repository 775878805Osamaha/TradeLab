import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';
import 'package:tradelab_flutter/replay/replay_mobile_controls.dart';

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
    // A historical Replay header must never reveal contemporary BID/ASK,
    // current feed status, or the later of these two verified source bars.
    final evidence = find.byKey(const Key('chart-provenance-header'));
    expect(tester.widget<Text>(evidence).data, 'Replay تاريخي · Binance');
    final tooltipFinder = find.ancestor(
      of: evidence, matching: find.byType(Tooltip));
    expect(tooltipFinder, findsOneWidget);
    final message = tester.widget<Tooltip>(tooltipFinder).message!;
    expect(message, contains('BTCUSDT'));
    expect(message, contains('آخر شمعة مكشوفة'));
    expect(message, isNot(contains('BID/ASK')));
    expect(message, isNot(contains('آخر شمعة مغلقة')));
    final firstBar = DateTime.fromMillisecondsSinceEpoch(
        1700000000000, isUtc: true);
    final firstTime = '${firstBar.hour.toString().padLeft(2, '0')}:'
        '${firstBar.minute.toString().padLeft(2, '0')} UTC';
    expect(message, contains(firstTime));
    expect(find.byKey(const Key('replay-speed-picker')), findsOneWidget);
    // Replay with no practice levels or rectangles has no viewport-snapshot
    // overlays. Touch samples should repaint the chart without rebuilding the
    // toolbar (same fast path used by the normal chart).
    final replayChart = find.byKey(const Key('chart-gesture-area'));
    await tester.drag(replayChart, const Offset(-40, 0));
    await tester.pumpAndSettle();
    final replayHeader = find.byKey(const Key('chart-reference-header'));
    final previousReplayHeader = tester.widget(replayHeader);
    await tester.drag(replayChart, const Offset(-45, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(identical(previousReplayHeader, tester.widget(replayHeader)), isTrue,
        reason: 'Normal Replay panning should not rebuild its toolbar');
    expect(tester.takeException(), isNull);
    // The user complained that toolbars and a giant trading strip obscure
    // the candles. They are HIDDEN until deliberately opened from settings.
    expect(find.byKey(const Key('chart-reference-toolbar')), findsNothing);
    expect(find.byKey(const Key('drawing-rail-cursor')), findsNothing);
    expect(find.byKey(const Key('replay-trading-buttons')), findsNothing);
    expect(find.byKey(const Key('replay-inline-trading')), findsNothing);
    expect(tester.getSize(find.byKey(const Key('chart-reference-header'))).height,
        48);
    await tester.tap(find.byKey(const Key('replay-start-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay-show-trading-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-inline-trading')), findsOneWidget);
    expect(find.byKey(const Key('replay-inline-buy')), findsOneWidget);
    expect(find.byKey(const Key('replay-inline-sell')), findsOneWidget);
    final flatten = tester.widget<OutlinedButton>(
        find.byKey(const Key('replay-flatten-trades')));
    expect(flatten.onPressed, isNull,
        reason: 'No open practice position may be flattened');
    await tester.tap(find.byKey(const Key('replay-inline-sell')));
    await tester.pumpAndSettle();
    expect(find.text('صفقة تدريب داخل Replay'), findsOneWidget);
    expect(tester.widget<DropdownButton<ReplaySide>>(
        find.byKey(const Key('replay-trade-side'))).value, ReplaySide.sell,
        reason: 'Sell ticket preselects SELL, never silently opens BUY');
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();

    // Hide again, proving trading tools do not occupy chart space by default.
    await tester.tap(find.byKey(const Key('replay-start-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay-show-trading-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-inline-trading')), findsNothing);

    await tester.tap(find.byKey(const Key('replay-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay-practice-order')));
    await tester.pumpAndSettle();
    expect(find.text('صفقة تدريب داخل Replay'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await tester.pumpAndSettle();

    expect(tester.widget<ReplayMobileControls>(
        find.byType(ReplayMobileControls)).tradeCount, 1);
    expect(find.byKey(const Key('replay-practice-levels-overlay')),
        findsOneWidget,
        reason: 'An entered practice trade should have chart markers');
    await tester.tap(find.byKey(const Key('replay-more-actions')));
    await tester.pumpAndSettle();
    expect(find.text('صفقاتي (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-practice-list')));
    await tester.pumpAndSettle();
    expect(find.text('صفقات التدريب التاريخية'), findsOneWidget);
    expect(find.textContaining('مفتوحة'), findsWidgets);
    await tester.tap(find.text('إغلاق').last);
    await tester.pumpAndSettle();

    // Reset may not destroy the settled trade without an explicit decision.
    final reset = find.byKey(const Key('replay-reset-start'));
    expect(reset, findsOneWidget);
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('العودة إلى بداية Replay'), findsOneWidget);
    expect(find.text('حفظ والعودة للبداية'), findsOneWidget);
    await tester.tap(find.text('إلغاء').last);
    await tester.pumpAndSettle();
    expect(tester.widget<ReplayMobileControls>(
        find.byType(ReplayMobileControls)).tradeCount, 1,
        reason: 'Cancelling reset must keep the existing practice trade');

    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay-confirm-reset')));
    await tester.pumpAndSettle();
    // The confirmed reset deliberately awaits a REAL durable FFI SQLite
    // write. FakeAsync pump(duration) advances widget time but not native
    // database I/O; yield to the real event loop as Flutter recommends.
    for (var attempt = 0;
        attempt < 25 &&
            tester.widget<ReplayMobileControls>(
                find.byType(ReplayMobileControls)).tradeCount != 0;
        attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
    }
    expect(find.text('العودة إلى بداية Replay'), findsNothing,
        reason: 'The approved reset dialog should have closed');
    expect(tester.widget<ReplayMobileControls>(
        find.byType(ReplayMobileControls)).tradeCount, 0,
        reason: 'Approved reset creates a new empty Replay practice session');
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('replay-practice-levels-overlay')),
        findsNothing,
        reason: 'A prior trade must not remain visible in the rewound chart');

    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
