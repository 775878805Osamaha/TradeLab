import 'dart:async';

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
      openedAtMs: old.openedAtMs, fee: old.fee);
  }

  @override
  Future<void> delete(String accountKey, int id) async {
    entries[accountKey]?.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<List<LedgerEntry>> list(String accountKey) async =>
      List.of(entries[accountKey] ?? []);
}

/// Delays only the first write, allowing deterministic button double-tap
/// and broker-account-switch races without any local SQLite fixture.
class _DelayedStore extends _FakeStore {
  final saveGate = Completer<void>();
  int started = 0;
  @override
  Future<void> add(LedgerEntry entry) async {
    started++;
    if (started == 1) await saveGate.future;
    await super.add(entry);
  }
}

class _DelayedCloseStore extends _FakeStore {
  final closeGate = Completer<void>();
  int closeStarted = 0;
  @override
  Future<void> closeTrade(String accountKey, int id,
      {required double exitPrice, required int timestampMs}) async {
    closeStarted++;
    await closeGate.future;
    await super.closeTrade(accountKey, id,
      exitPrice: exitPrice, timestampMs: timestampMs);
  }
}

/// A write that reaches durable storage but loses its acknowledgement.
/// The controller must re-read the record before surfacing the error.
class _CommitThenFailStore extends _FakeStore {
  @override
  Future<void> add(LedgerEntry entry) async {
    await super.add(entry);
    throw StateError('network-style acknowledgement lost after local commit');
  }
}

/// Mimics an interrupted view lifecycle while the store is writing.
class _DisposeDuringWriteStore extends _FakeStore {
  final gate = Completer<void>();
  final closed = Completer<void>();
  bool committed = false;
  bool closedBeforeCommit = false;

  @override
  Future<void> add(LedgerEntry entry) async {
    await gate.future;
    await super.add(entry);
    committed = true;
  }

  @override
  Future<void> close() async {
    closedBeforeCommit = !committed;
    closed.complete();
  }
}

class _DisposeDuringReadStore extends _FakeStore {
  final readGate = Completer<void>();
  final closed = Completer<void>();
  bool readCompleted = false;
  bool closedBeforeRead = false;

  @override
  Future<List<LedgerEntry>> list(String accountKey) async {
    await readGate.future;
    final result = await super.list(accountKey);
    readCompleted = true;
    return result;
  }

  @override
  Future<void> close() async {
    closedBeforeRead = !readCompleted;
    closed.complete();
  }
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

  test('double-tapping save never inserts a duplicate local paper entry',
      () async {
    final store = _DelayedStore();
    final journal = PaperJournalController(store: store);
    addTearDown(journal.dispose);
    await journal.useAccount('101');
    final entry = LedgerEntry(id: 0, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000, amount: 1000);

    final first = journal.add(entry);
    expect(journal.busy, isTrue,
      reason: 'The write lock must engage synchronously before the first await');
    await expectLater(journal.add(entry), throwsStateError);
    expect(store.started, 1);
    expect(journal.entries, isEmpty);

    store.saveGate.complete();
    await first;
    expect(journal.busy, isFalse);
    expect(journal.entries, hasLength(1));
    expect(store.entries['ctrader:101'], hasLength(1));
  });

  test('account switching during a save never publishes the old journal',
      () async {
    final store = _DelayedStore();
    final journal = PaperJournalController(store: store);
    addTearDown(journal.dispose);
    await journal.useAccount('101');
    final entry = LedgerEntry(id: 0, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000, amount: 250);
    final first = journal.add(entry);

    await journal.useAccount('202');
    expect(journal.accountKey, 'ctrader:202');
    expect(journal.entries, isEmpty);
    expect(journal.busy, isTrue,
        reason: 'An in-flight write remains locked even after new-account read');
    await expectLater(journal.add(LedgerEntry(
      id: 0, accountKey: journal.accountKey, kind: LedgerKind.deposit,
      timestampMs: 1700000000000, amount: 500)), throwsStateError);

    store.saveGate.complete();
    await first;
    expect(journal.busy, isFalse);
    expect(journal.entries, isEmpty,
      reason: 'The completed write belongs to the old broker scope');
    await journal.useAccount('101');
    expect(journal.entries.single.amount, 250);
    await journal.useAccount('202');
    expect(journal.entries, isEmpty);
  });

  test('duplicate close and delete cannot race a pending position close',
      () async {
    final store = _DelayedCloseStore();
    final journal = PaperJournalController(store: store);
    addTearDown(journal.dispose);
    await journal.useAccount('101');
    const position = LedgerEntry(
      id: 1, accountKey: 'ctrader:101', kind: LedgerKind.openTrade,
      timestampMs: 1700000000000, openedAtMs: 1700000000000,
      symbol: 'XAUUSD', side: PaperSide.buy, quantity: 1,
      entryPrice: 2000);
    await journal.add(position);

    final first = journal.closeTrade(position,
      exitPrice: 2020, timestampMs: 1700000005000);
    expect(journal.busy, isTrue);
    await expectLater(journal.closeTrade(position,
      exitPrice: 2020, timestampMs: 1700000005000), throwsStateError);
    await expectLater(journal.delete(position.id), throwsStateError);
    expect(store.closeStarted, 1);
    store.closeGate.complete();
    await first;

    expect(journal.busy, isFalse);
    expect(journal.entries, hasLength(1));
    expect(journal.entries.single.kind, LedgerKind.closedTrade);
    expect(journal.entries.single.realizedPnl, 20);
  });


  test('a committed row remains visible when its write acknowledgement fails',
      () async {
    final store = _CommitThenFailStore();
    final journal = PaperJournalController(store: store);
    addTearDown(journal.dispose);
    await journal.useAccount('101');
    final entry = LedgerEntry(
      id: 0, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000, amount: 125);
    await expectLater(journal.add(entry), throwsStateError);
    expect(journal.busy, isFalse);
    expect(journal.entries, hasLength(1),
        reason: 'After an uncertain write, read actual SQLite state');
    expect(journal.entries.single.amount, 125);
    expect(store.entries['ctrader:101'], hasLength(1));
  });

  test('dispose waits for a pending write before closing the database',
      () async {
    final store = _DisposeDuringWriteStore();
    final journal = PaperJournalController(store: store);
    await journal.useAccount('101');
    final saving = journal.add(LedgerEntry(
      id: 0, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000, amount: 42));
    expect(journal.busy, isTrue);

    journal.dispose();
    expect(store.closed.isCompleted, isFalse,
        reason: 'Never close SQLite while its commit is pending');
    store.gate.complete();
    await saving;
    await store.closed.future.timeout(const Duration(seconds: 2));
    expect(store.committed, isTrue);
    expect(store.closedBeforeCommit, isFalse);
    expect(store.entries['ctrader:101'], hasLength(1));
  });

  test('dispose waits for a pending journal read before closing the database',
      () async {
    final store = _DisposeDuringReadStore();
    final journal = PaperJournalController(store: store);
    final loading = journal.useAccount('101');
    expect(journal.busy, isTrue);
    journal.dispose();
    expect(store.closed.isCompleted, isFalse);
    store.readGate.complete();
    await loading;
    await store.closed.future.timeout(const Duration(seconds: 2));
    expect(store.closedBeforeRead, isFalse);
  });

}
