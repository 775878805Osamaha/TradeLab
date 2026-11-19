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

  for (final width in <double>[320, 390]) {
    testWidgets('57 real local journal rows remain accessible in 25-row pages '
        'and reset on account switch at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      final store = _ResultsStore();
      final journal = PaperJournalController(store: store);
      addTearDown(market.dispose);
      addTearDown(journal.dispose);

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (var i = 1; i <= 57; i++) {
        final closedAt = now - (58 - i) * 60000;
        store.rows.add(LedgerEntry(
          id: i,
          accountKey: 'ctrader:101',
          kind: LedgerKind.closedTrade,
          timestampMs: closedAt,
          openedAtMs: closedAt - 60000,
          symbol: 'XAUUSD',
          side: PaperSide.buy,
          quantity: 1,
          entryPrice: 100,
          exitPrice: 101,
        ));
      }
      await journal.useAccount('101');
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ResultsScreen(controller: market, journal: journal),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-net-profit-hero')), findsOneWidget,
          reason: 'Overview keeps its verified local profit summary');
      final tab = find.byKey(const Key('results-tab-2'));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results-net-profit-hero')), findsNothing,
          reason: 'Journal should not waste the viewport on overview cards');
      expect(find.byKey(const Key('results-local-source-note')), findsOneWidget);
      expect(find.byKey(const Key('results-closed-trade-57')), findsOneWidget);
      expect(find.byKey(const Key('results-closed-trade-33')), findsOneWidget);
      expect(find.byKey(const Key('results-closed-trade-32')), findsNothing);
      expect(find.text('عرض 25 من 57 صفقة مغلقة'), findsOneWidget);

      final list = find.descendant(
          of: find.byKey(const Key('results-dashboard-list')),
          matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(
          find.byKey(const Key('results-more-closed-trades')), 290,
          scrollable: list, maxScrolls: 24);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('results-more-closed-trades')));
      await tester.pumpAndSettle();
      expect(find.text('عرض 50 من 57 صفقة مغلقة'), findsOneWidget);
      expect(find.byKey(const Key('results-closed-trade-8')), findsOneWidget);
      expect(find.byKey(const Key('results-closed-trade-7')), findsNothing);

      await tester.scrollUntilVisible(
          find.byKey(const Key('results-more-closed-trades')), 290,
          scrollable: list, maxScrolls: 24);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('results-more-closed-trades')));
      await tester.pumpAndSettle();
      expect(find.text('عرض 57 من 57 صفقة مغلقة'), findsOneWidget);
      expect(find.byKey(const Key('results-closed-trade-1')), findsOneWidget);
      expect(find.byKey(const Key('results-more-closed-trades')), findsNothing);

      await journal.useAccount('202');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-closed-trade-57')), findsNothing);
      expect(find.textContaining('57 صفقة مغلقة'), findsNothing);
      await journal.useAccount('101');
      await tester.pumpAndSettle();
      expect(find.text('عرض 25 من 57 صفقة مغلقة'), findsOneWidget,
          reason: 'A different broker account never keeps another page cursor');
      expect(find.byKey(const Key('results-closed-trade-32')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[320, 390]) {
    testWidgets('57 local open positions use preview and 25-row journal pages '
        'with account isolation at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      final store = _ResultsStore();
      final journal = PaperJournalController(store: store);
      addTearDown(market.dispose);
      addTearDown(journal.dispose);

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (var i = 1; i <= 57; i++) {
        final openedAt = now - (58 - i) * 60000;
        store.rows.add(LedgerEntry(
          id: i,
          accountKey: 'ctrader:101',
          kind: LedgerKind.openTrade,
          timestampMs: openedAt,
          openedAtMs: openedAt,
          symbol: 'XAUUSD',
          side: PaperSide.buy,
          quantity: 1,
          entryPrice: 2000 + i.toDouble(),
        ));
      }
      await journal.useAccount('101');
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ResultsScreen(controller: market, journal: journal),
      )));
      await tester.pumpAndSettle();

      // On narrow phones, the large Results overview precedes the open-
      // positions section. Scroll to each row before asserting its content.
      final list = find.descendant(
          of: find.byKey(const Key('results-dashboard-list')),
          matching: find.byType(Scrollable)).first;
      Future<void> reveal(String key) async {
        await tester.scrollUntilVisible(
          find.byKey(Key(key)), 290,
          scrollable: list, maxScrolls: 35);
        await tester.pumpAndSettle();
      }

      await reveal('results-open-trade-57');
      expect(find.byKey(const Key('results-open-trade-57')), findsOneWidget);
      await reveal('results-open-trade-53');
      expect(find.byKey(const Key('results-open-trade-53')), findsOneWidget);
      expect(find.byKey(const Key('results-open-trade-52')), findsNothing);
      await reveal('results-open-trades-count');
      expect(find.text('عرض 5 من 57 مركزًا تجريبيًا مفتوحًا'),
          findsOneWidget);
      await reveal('results-all-open-trades');
      await tester.tap(find.byKey(const Key('results-all-open-trades')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results-tab-2')), findsOneWidget);
      await reveal('results-open-trade-57');
      expect(find.byKey(const Key('results-open-trade-57')), findsOneWidget);
      await reveal('results-open-trade-33');
      expect(find.byKey(const Key('results-open-trade-33')), findsOneWidget);
      expect(find.byKey(const Key('results-open-trade-32')), findsNothing);
      await reveal('results-open-trades-count');
      expect(find.text('عرض 25 من 57 مركزًا تجريبيًا مفتوحًا'),
          findsOneWidget);

      await reveal('results-more-open-trades');
      await tester.tap(find.byKey(const Key('results-more-open-trades')));
      await tester.pumpAndSettle();
      await reveal('results-open-trade-8');
      expect(find.byKey(const Key('results-open-trade-8')), findsOneWidget);
      expect(find.byKey(const Key('results-open-trade-7')), findsNothing);
      await reveal('results-open-trades-count');
      expect(find.text('عرض 50 من 57 مركزًا تجريبيًا مفتوحًا'),
          findsOneWidget);

      await reveal('results-more-open-trades');
      await tester.tap(find.byKey(const Key('results-more-open-trades')));
      await tester.pumpAndSettle();
      await reveal('results-open-trade-1');
      expect(find.byKey(const Key('results-open-trade-1')), findsOneWidget);
      await reveal('results-open-trades-count');
      expect(find.text('عرض 57 من 57 مركزًا تجريبيًا مفتوحًا'),
          findsOneWidget);
      expect(find.byKey(const Key('results-more-open-trades')), findsNothing);

      await journal.useAccount('202');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-open-trade-57')), findsNothing);
      expect(find.textContaining('57 مركزًا تجريبيًا'), findsNothing);
      await journal.useAccount('101');
      await tester.pumpAndSettle();
      await reveal('results-open-trades-count');
      expect(find.text('عرض 25 من 57 مركزًا تجريبيًا مفتوحًا'),
          findsOneWidget,
          reason: 'Switching broker accounts resets open-position pagination');
      expect(find.byKey(const Key('results-open-trade-32')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
