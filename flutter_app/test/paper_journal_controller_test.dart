import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

class _FakeStore implements PaperJournalStore {
  final Map<String, List<LedgerEntry>> entries = {};

  @override
  Future<void> add(LedgerEntry entry) async {
    entries.putIfAbsent(entry.accountKey, () => []).add(entry);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> closeTrade(String accountKey, int id,
      {required double exitPrice, required int timestampMs}) async {
    final rows = entries[accountKey] ?? [];
    final index = rows.indexWhere((entry) => entry.id == id &&
      entry.kind == LedgerKind.openTrade && entry.timestampMs <= timestampMs);
    if (index < 0) throw StateError('not an open trade');
    final old = rows[index];
    rows[index] = LedgerEntry(id: old.id, accountKey: old.accountKey,
      kind: LedgerKind.closedTrade, timestampMs: timestampMs,
      symbol: old.symbol, side: old.side, quantity: old.quantity,
      entryPrice: old.entryPrice, exitPrice: exitPrice,
      openedAtMs: old.openedAtMs, fee: old.fee,
      stopLoss: old.stopLoss, takeProfit: old.takeProfit);
  }

  @override
  Future<void> delete(String accountKey, int id) async {
    entries[accountKey]?.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<List<LedgerEntry>> list(String accountKey) async =>
      List.of(entries[accountKey] ?? []);
}

void main() {
  test('switching cTrader accounts isolates local paper journal entries', () async {
    final journal = PaperJournalController(store: _FakeStore());
    addTearDown(journal.dispose);
    await journal.useAccount('123');
    expect(journal.accountKey, 'ctrader:123');
    await journal.add(LedgerEntry(id: 1, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000, amount: 1000));
    expect(journal.entries.length, 1);
    await journal.useAccount('999');
    expect(journal.entries, isEmpty);
    await journal.useAccount('123');
    expect(journal.entries.single.amount, 1000);
  });
}
