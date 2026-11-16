import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

void main() {
  testWidgets('tapping a Markets row opens the selected cTrader chart',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final market = MarketController(
      api: MarketApi(client: MockClient((_) async =>
          http.Response('{"error":"offline"}', 503))));
    addTearDown(market.dispose);

    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قائمة المراقبة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-open-chart-EURUSD')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(find.text('EURUSD'), findsWidgets);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget,
        reason: 'No cTrader account means no genuine EURUSD OHLC source');

    await tester.tap(find.text('قائمة المراقبة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-open-chart-XAUUSD')));
    await tester.pumpAndSettle();
    expect(find.text('XAUUSD'), findsWidgets);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching from loaded Binance history to unlinked cTrader '
      'never displays an earlier symbol as gold candles', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/v3/klines') {
        final rows = List.generate(120, (i) {
          final timestamp = 1700000000000 + i * 900000;
          return [timestamp, '35000', '35100', '34900', '35050',
            '1', timestamp + 899999];
        });
        return http.Response(jsonEncode(rows), 200);
      }
      return http.Response('{"error":"offline"}', 503);
    });
    final market = MarketController(api: MarketApi(client: client));
    addTearDown(market.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قائمة المراقبة').last);
    await tester.pumpAndSettle();
    final btc = find.byKey(const Key('market-open-chart-BTCUSDT'));
    await tester.ensureVisible(btc);
    await tester.tap(btc);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsNothing,
        reason: 'The mocked Binance history exists in this isolated test');
    expect(find.text('BTCUSDT'), findsWidgets);

    await tester.tap(find.text('قائمة المراقبة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-open-chart-XAUUSD')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget,
        reason: 'BTC candle cache must never appear under XAUUSD');
    expect(tester.takeException(), isNull);
  });
}
