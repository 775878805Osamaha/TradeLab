import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/data/watchlist_favorites_store.dart';
import 'package:tradelab_flutter/screens/markets_screen.dart';

class _MemoryWatchlistStore implements WatchlistFavoritesStore {
  _MemoryWatchlistStore(this.saved);

  Set<String> saved;
  int saves = 0;

  @override
  Future<Set<String>> load() async => Set<String>.of(saved);

  @override
  Future<void> save(Set<String> symbols) async {
    saved = Set<String>.of(symbols);
    saves++;
  }

  @override
  Future<void> close() async {}
}

/// Drives the Watchlist with source timestamps, without connecting to or
/// inventing a real cTrader account during offline Flutter widget tests.
class _WatchlistQuoteController extends MarketController {
  MarketQuote? sourceQuote;
  bool linked = true;

  @override
  bool get ctraderConnected => linked;

  @override
  MarketQuote? recentQuoteFor(TradeSymbol symbol) {
    final quote = sourceQuote;
    if (!linked || quote == null || quote.symbol != symbol.code ||
        quote.source != symbol.source) return null;
    try {
      quote.assertFresh(
        nowMs: DateTime.now().toUtc().millisecondsSinceEpoch);
      return quote;
    } on MarketDataException {
      return null;
    }
  }

  void publish(MarketQuote? quote) {
    sourceQuote = quote;
    notifyListeners();
  }

  void changeConnection(bool connected) {
    linked = connected;
    notifyListeners();
  }
}

void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('favorite survives watchlist widget restart at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MarketController();
      addTearDown(controller.dispose);
      final store = _MemoryWatchlistStore({'XAUUSD', 'EURUSD'});

      Widget screen() => MaterialApp(home: Scaffold(
        body: MarketsScreen(
          controller: controller, favoritesStore: store,
        ),
      ));
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final crypto = find.byKey(const Key('watchlist-filter-كريبتو'));
      await tester.ensureVisible(crypto);
      await tester.tap(crypto);
      await tester.pumpAndSettle();
      final star = find.byKey(const Key('watchlist-favorite-BTCUSDT'));
      expect(star, findsOneWidget);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(store.saved, contains('BTCUSDT'));
      expect(store.saves, 1);

      await tester.tap(find.byKey(const Key('watchlist-favorites-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('market-open-chart-BTCUSDT')),
          findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final reloadedCrypto = find.byKey(
          const Key('watchlist-filter-كريبتو'));
      await tester.ensureVisible(reloadedCrypto);
      await tester.tap(reloadedCrypto);
      await tester.pumpAndSettle();
      final again = tester.widget<IconButton>(
          find.byKey(const Key('watchlist-favorite-BTCUSDT')));
      expect(again.tooltip, 'إزالة من المفضلة');
      expect(store.saves, 1,
          reason: 'Restoring preferences must not write or duplicate edits');
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in <double>[320, 390]) {
    testWidgets('watchlist refuses expired or unlinked cTrader BID at '
        '${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _WatchlistQuoteController();
      addTearDown(controller.dispose);
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final store = _MemoryWatchlistStore({'XAUUSD'});
      // A raw cached price alone is NOT proof of a current broker quote.
      controller.forexPrices['XAUUSD'] = 3987.5;
      controller.sourceQuote = MarketQuote(
        symbol: 'XAUUSD', source: TradeSource.ctrader,
        bid: 3987.5, ask: 3987.7,
        timestampMs: nowMs - 120000,
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: MarketsScreen(controller: controller, favoritesStore: store),
      )));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('watchlist-search')), 'XAUUSD');
      await tester.pumpAndSettle();
      expect(find.text('3987.50'), findsNothing,
          reason: 'Old BID is never advertised as a live price');
      expect(find.text('انتهت صلاحية السعر — حدّث الأسعار'), findsOneWidget);

      controller.publish(MarketQuote(
        symbol: 'XAUUSD', source: TradeSource.ctrader,
        bid: 3991.25, ask: 3991.45,
        timestampMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      ));
      await tester.pumpAndSettle();
      expect(find.text('3991.25'), findsOneWidget);
      expect(find.text('سعر BID حديث من cTrader'), findsOneWidget);

      controller.changeConnection(false);
      await tester.pumpAndSettle();
      expect(find.text('3991.25'), findsNothing,
          reason: 'Switching off broker session hides even a recent BID');
      expect(find.text('يتطلب ربط cTrader'), findsOneWidget);

      controller.changeConnection(true);
      controller.publish(MarketQuote(
        symbol: 'XAUUSD', source: TradeSource.ctrader,
        bid: 3999, ask: 4000, timestampMs: nowMs - 180000,
      ));
      await tester.pumpAndSettle();
      expect(find.text('3999.00'), findsNothing);
      expect(find.text('انتهت صلاحية السعر — حدّث الأسعار'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }


}
