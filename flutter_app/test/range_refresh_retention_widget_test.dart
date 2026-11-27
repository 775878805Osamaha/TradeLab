import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/main.dart';

/// A fixture source is permitted in tests, not in production market data.
class _VerifiedBidFixtureController extends MarketController {
  _VerifiedBidFixtureController() {
    accountId = 'fixture-account';
  }

  @override
  bool get ctraderConnected => true;

  @override
  Future<List<MarketBar>> history(TradeSymbol symbol, String timeframe,
      {DateTime? before}) async => const <MarketBar>[];

  @override
  Future<double> pointSize(TradeSymbol symbol) async => .01;

  Completer<List<MarketTick>>? heldRefresh;
  int rangeRequests = 0;

  @override
  Future<List<MarketTick>> rangeTicksBetween(TradeSymbol symbol, {
    required int fromMs,
    required int toMs,
  }) async {
    rangeRequests++;
    if (heldRefresh != null) return heldRefresh!.future;
    // Valid authenticated-window-shaped fixture; real app still calls cTrader.
    // One source jump produces > 40 Range bars and avoids background backfill.
    return <MarketTick>[
      MarketTick(toMs - 2000, 100),
      MarketTick(toMs - 1999, 115),
    ];
  }

  @override
  Future<MarketQuote> paperQuote(TradeSymbol symbol) async =>
      throw const MarketDataException('Test quote not configured');
}

void main() {
  testWidgets('a failed same-source BID refresh preserves real Range chart',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final market = _VerifiedBidFixtureController();
    addTearDown(market.dispose);
    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chart-quick-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-quick-chart-type')));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('chart-type-grid')),
        const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-kind-range')));
    await tester.pumpAndSettle();
    expect(find.text('إعدادات شموع المدى'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '25'));
    await tester.pumpAndSettle();

    expect(market.rangeRequests, greaterThan(0));
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    expect(find.textContaining('شموع محسوبة من تيكات BID'), findsOneWidget);

    // The second exact source request cannot finish yet. Existing, already
    // verified candles must stay visible, with a clearly labeled refresh.
    final held = Completer<List<MarketTick>>();
    market.heldRefresh = held;
    await tester.tap(find.byKey(const Key('chart-quick-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-quick-range')));
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('range-refresh-verified-bid'));
    expect(refresh, findsOneWidget);
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pump();
    // SQLite cache misses may complete asynchronously; the exact pending
    // fake cTrader request never returns before this assertion.
    for (var i = 0; i < 20 && market.rangeRequests < 2; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(market.rangeRequests, greaterThanOrEqualTo(2));
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    expect(find.textContaining('تحديث BID جارٍ'), findsOneWidget);

    held.completeError(const MarketDataException(
        'اختبار: فشل مؤقت لدى المصدر'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    expect(find.textContaining('شموع محسوبة من تيكات BID'), findsOneWidget);
    expect(find.textContaining('اختبار: فشل مؤقت لدى المصدر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
