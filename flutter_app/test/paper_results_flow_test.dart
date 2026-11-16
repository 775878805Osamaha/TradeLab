import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/screens/results_screen.dart';

class _ResultsStore implements PaperJournalStore {
  final rows = <LedgerEntry>[];
  @override
  Future<List<LedgerEntry>> list(String key) async =>
      rows.where((entry) => entry.accountKey == key).toList(growable: false);

  @override
  Future<void> add(LedgerEntry entry) async {
    rows.add(LedgerEntry(
      id: rows.length + 1,
      accountKey: entry.accountKey,
      kind: entry.kind,
      timestampMs: entry.timestampMs,
      amount: entry.amount,
      symbol: entry.symbol,
      side: entry.side,
      quantity: entry.quantity,
      entryPrice: entry.entryPrice,
      exitPrice: entry.exitPrice,
      openedAtMs: entry.openedAtMs,
      fee: entry.fee,
    ));
  }

  @override
  Future<void> closeTrade(String key, int id,
      {required double exitPrice, required int timestampMs}) async {
    final index = rows.indexWhere((entry) =>
        entry.accountKey == key && entry.id == id &&
        entry.kind == LedgerKind.openTrade);
    if (index < 0) throw StateError('No open trade in this account');
    final old = rows[index];
    rows[index] = LedgerEntry(
      id: old.id, accountKey: key, kind: LedgerKind.closedTrade,
      timestampMs: timestampMs, openedAtMs: old.openedAtMs,
      symbol: old.symbol, side: old.side, quantity: old.quantity,
      entryPrice: old.entryPrice, exitPrice: exitPrice, fee: old.fee,
    );
  }

  @override
  Future<void> delete(String key, int id) async {
    rows.removeWhere((entry) => entry.accountKey == key && entry.id == id);
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('results reflect committed local trade, not an open position',
      (tester) async {
    final controller = MarketController();
    final journal = PaperJournalController(store: _ResultsStore());
    addTearDown(controller.dispose);
    addTearDown(journal.dispose);

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await journal.useAccount('101');
    await journal.add(LedgerEntry(
      id: 0, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: now - 120000,
      amount: 1000,
    ));
    await journal.add(LedgerEntry(
      id: 0, accountKey: journal.accountKey,
      kind: LedgerKind.openTrade, timestampMs: now - 60000,
      openedAtMs: now - 60000,
      symbol: 'XAUUSD', side: PaperSide.buy, quantity: 2,
      entryPrice: 100,
    ));

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ResultsScreen(
        controller: controller, journal: journal)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-ledger-entry')), findsOneWidget);
    expect(find.text('المراكز التجريبية المفتوحة'), findsOneWidget);
    expect(find.text('إغلاق تجريبي'), findsOneWidget);
    expect(calculateLedgerReport(journal.entries).tradeCount, 0,
        reason: 'An open position is not a realized closed trade');
    expect(find.text('+20.00 USD'), findsNothing,
        reason: 'An open trade has no verified realized P&L');

    final open = journal.entries.firstWhere(
        (entry) => entry.kind == LedgerKind.openTrade);
    await journal.closeTrade(open, exitPrice: 110, timestampMs: now);
    await tester.pumpAndSettle();

    expect(find.textContaining('+20.00 USD'), findsWidgets,
        reason: 'Profit is computed only from the saved closed trade');
    expect(find.text('إغلاق تجريبي'), findsNothing);

    await journal.useAccount('202');
    await tester.pumpAndSettle();
    expect(find.textContaining('+20.00 USD'), findsNothing,
        reason: 'A broker switch never leaks another journal account P&L');

    await journal.useAccount('101');
    await tester.pumpAndSettle();
    expect(find.textContaining('+20.00 USD'), findsWidgets,
        reason: 'Returning to the original account restores its results');
    expect(tester.takeException(), isNull);
  });
}
