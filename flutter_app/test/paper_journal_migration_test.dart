import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

void main() {
  late String dbPath;
  const key = 'ctrader:99';
  final now = DateTime.utc(2026, 11, 9).millisecondsSinceEpoch;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = path.join(await getDatabasesPath(), 'tradelab_flutter_paper_v1.db');
    await deleteDatabase(dbPath);
    final legacy = await openDatabase(dbPath, version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE ledger_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_key TEXT NOT NULL, kind TEXT NOT NULL,
            timestamp_ms INTEGER NOT NULL, amount REAL,
            symbol TEXT, side TEXT, quantity REAL,
            entry_price REAL, exit_price REAL,
            fee REAL NOT NULL DEFAULT 0, opened_at_ms INTEGER
          )
        ''');
        await db.insert('ledger_entries', {
          'account_key': key, 'kind': 'deposit',
          'timestamp_ms': now - 10000, 'amount': 1000,
        });
      });
    await legacy.close();
  });

  tearDownAll(() async => deleteDatabase(dbPath));

  test('v1 ledger migrates to v2 without losing deposits or positions', () async {
    final store = SqlitePaperJournalStore();
    final legacy = await store.list(key);
    expect(legacy, hasLength(1));
    expect(legacy.single.amount, 1000);
    expect(legacy.single.stopLoss, isNull);
    await store.add(LedgerEntry(id: 0, accountKey: key,
      kind: LedgerKind.openTrade, timestampMs: now,
      openedAtMs: now, symbol: 'XAUUSD', side: PaperSide.buy,
      quantity: 0.1, entryPrice: 2000,
      stopLoss: 1990, takeProfit: 2020));
    final rows = await store.list(key);
    expect(rows, hasLength(2));
    expect(rows.last.stopLoss, 1990);
    expect(rows.last.takeProfit, 2020);
    await store.close();

    final reopened = SqlitePaperJournalStore();
    final restored = await reopened.list(key);
    expect(restored.first.amount, 1000);
    expect(restored.last.stopLoss, 1990);
    await reopened.close();
  });
}
