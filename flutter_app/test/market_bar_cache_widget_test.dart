import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_bar_store.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/main.dart';

class _SavedBars extends MarketBarStore {
  _SavedBars(this.bars);

  final List<MarketBar> bars;

  @override
  Future<List<MarketBar>> readLatest({required TradeSource source,
      required String account, required String symbol,
      required String timeframe, int limit = 1200}) async => bars;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline Binance chart shows verified saved OHLC as local history',
      (tester) async {
    final start = DateTime.utc(2026, 11, 8).millisecondsSinceEpoch;
    final store = _SavedBars([
        MarketBar(start, const TradeCandle(70000, 70200, 69900, 70100)),
        MarketBar(start + 900000,
            const TradeCandle(70100, 70300, 70000, 70200)),
      ]);
    final controller = MarketController(api: MarketApi(
      client: MockClient((_) async => http.Response('{}', 503))));
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TradeLabApp(controller: controller,
      barStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();

    expect(find.text('أرشيف محلي'), findsOneWidget);
    expect(find.textContaining('شموع تاريخية محفوظة محليًا'), findsOneWidget);
    expect(find.textContaining('Binance لا يستجيب'), findsOneWidget);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
