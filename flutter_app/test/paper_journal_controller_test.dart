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
