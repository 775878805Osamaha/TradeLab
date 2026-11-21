import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/watchlist_favorites_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<String> isolatedPath() async => path.join(
    await getDatabasesPath(),
    'tradelab_watchlist_test_${DateTime.now().microsecondsSinceEpoch}.db',
  );

  test('SQLite favorites survive app close, and an intentionally empty set stays empty',
      () async {
    final file = await isolatedPath();
    final original = SqliteWatchlistFavoritesStore(databasePath: file);
    try {
      expect(await original.load(), {'XAUUSD', 'EURUSD'},
          reason: 'Only a new database receives default stars');
      await original.save({'XAUUSD', 'BTCUSDT'});
      expect(await original.load(), {'XAUUSD', 'BTCUSDT'});
    } finally {
      await original.close();
    }

    final reopened = SqliteWatchlistFavoritesStore(databasePath: file);
    try {
      expect(await reopened.load(), {'XAUUSD', 'BTCUSDT'});
      await reopened.save({});
      expect(await reopened.load(), isEmpty);
    } finally {
      await reopened.close();
    }

    final afterEmptyRestart = SqliteWatchlistFavoritesStore(databasePath: file);
    try {
      expect(await afterEmptyRestart.load(), isEmpty,
          reason: 'Removing all favorites must not reinsert initial stars');
    } finally {
      await afterEmptyRestart.close();
      await deleteDatabase(file);
    }
  });

  test('rapid star edits commit in user order without older write winning',
      () async {
    final file = await isolatedPath();
    final store = SqliteWatchlistFavoritesStore(databasePath: file);
    try {
      final edits = [
        store.save({'XAUUSD'}),
        store.save({'EURUSD', 'BTCUSDT'}),
        store.save({'ETHUSDT'}),
      ];
      await Future.wait(edits);
      expect(await store.load(), {'ETHUSDT'},
          reason: 'The last chosen favorite set is authoritative');
      await store.save({'XAUUSD'});
      expect(await store.load(), {'XAUUSD'});
    } finally {
      await store.close();
      await deleteDatabase(file);
    }
  });
}
