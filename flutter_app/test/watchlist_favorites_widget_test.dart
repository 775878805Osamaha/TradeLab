import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
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
}
