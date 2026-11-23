import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

/// Exercises the REAL SQLite implementation on an isolated throwaway file.
/// It is a desktop SQLite integration test, not an Android-device test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<String> isolatedPath() async => path.join(
    await getDatabasesPath(),
    'tradelab_paper_test_${DateTime.now().microsecondsSinceEpoch}.db',
  );

  const accountA = 'ctrader:101';
  const accountB = 'ctrader:202';
  const openedAt = 1700000000000;

  test('real SQLite records survive store close and reopen per account',
      () async {
    final file = await isolatedPath();
    final first = SqlitePaperJournalStore(databasePath: file);
    await first.add(const LedgerEntry(
      id: 0, accountKey: accountA,
      kind: LedgerKind.deposit, timestampMs: openedAt - 60000,
      amount: 1000,
    ));
    await first.add(const LedgerEntry(
      id: 0, accountKey: accountA,
      kind: LedgerKind.openTrade, timestampMs: openedAt,
      openedAtMs: openedAt, symbol: 'XAUUSD',
      side: PaperSide.buy, quantity: 2, entryPrice: 2000,
      fee: 1,
    ));
    await first.add(const LedgerEntry(
      id: 0, accountKey: accountB, kind: LedgerKind.deposit,
      timestampMs: openedAt, amount: 500,
    ));
    final open = (await first.list(accountA)).singleWhere(
      (entry) => entry.kind == LedgerKind.openTrade);
    expect(open.id, greaterThan(0));
    await first.close();

    final reopened = SqlitePaperJournalStore(databasePath: file);
    try {
      final savedA = await reopened.list(accountA);
      final savedB = await reopened.list(accountB);
      expect(savedA, hasLength(2));
      expect(savedA.first.amount, 1000);
      expect(savedA.last.id, open.id);
      expect(savedA.last.entryPrice, 2000);
      expect(savedA.last.quantity, 2);
      expect(savedA.last.openedAtMs, openedAt);
      expect(savedB, hasLength(1));
      expect(savedB.single.amount, 500);
      expect(calculateLedgerReport(savedA).tradeCount, 0,
        reason: 'Unclosed positions cannot invent realized profits');

      await reopened.closeTrade(accountA, open.id,
        exitPrice: 2020, timestampMs: openedAt + 60000);
      final closed = (await reopened.list(accountA)).last;
      expect(closed.kind, LedgerKind.closedTrade);
      expect(closed.openedAtMs, openedAt);
      expect(closed.exitPrice, 2020);
      expect(closed.fee, 1);
      expect(closed.realizedPnl, 39);
      expect(calculateLedgerReport(await reopened.list(accountA)).netProfit,
        39);
    } finally {
      await reopened.close();
    }

    final afterRestart = SqlitePaperJournalStore(databasePath: file);
    try {
      final rows = await afterRestart.list(accountA);
      expect(rows.singleWhere((entry) => entry.kind == LedgerKind.closedTrade)
        .realizedPnl, 39);
      expect((await afterRestart.list(accountB)).single.amount, 500);
    } finally {
      await afterRestart.close();
      await deleteDatabase(file);
    }
  });

  test('SQLite rejects double close and wrong-account changes by row ID',
      () async {
    final file = await isolatedPath();
    final store = SqlitePaperJournalStore(databasePath: file);
    try {
      await store.add(const LedgerEntry(
        id: 0, accountKey: accountA, kind: LedgerKind.openTrade,
        timestampMs: openedAt, openedAtMs: openedAt,
        symbol: 'XAUUSD', side: PaperSide.sell,
        quantity: 1, entryPrice: 2000,
      ));
      final id = (await store.list(accountA)).single.id;
      await expectLater(
        store.closeTrade(accountB, id, exitPrice: 1990,
          timestampMs: openedAt + 1000),
        throwsStateError,
      );
      await expectLater(
        store.closeTrade(accountA, id, exitPrice: 1990,
          timestampMs: openedAt - 1),
        throwsStateError,
      );
      expect((await store.list(accountA)).single.kind,
          LedgerKind.openTrade);
      await store.closeTrade(accountA, id, exitPrice: 1990,
        timestampMs: openedAt + 1000);
      await expectLater(
        store.closeTrade(accountA, id, exitPrice: 1980,
          timestampMs: openedAt + 2000),
        throwsStateError,
      );
      await store.delete(accountB, id);
      expect((await store.list(accountA)).single.exitPrice, 1990,
        reason: 'Deleting in another account cannot remove this trade');
      await store.delete(accountA, id);
      expect(await store.list(accountA), isEmpty);
    } finally {
      await store.close();
      await deleteDatabase(file);
    }
  });
}
