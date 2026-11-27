import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

/// Native-Android SQLite smoke test.
/// No cTrader login, network calls, payment, or broker orders are involved.
/// Uses its own throwaway database; production journal is never opened.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android journal survives reopening and shows isolated results',
      (tester) async {
    final databasePath = path.join(await getDatabasesPath(),
      'tradelab_paper_android_smoke_${DateTime.now().microsecondsSinceEpoch}.db');
    final market = MarketController()..accountId = '101';
    SqlitePaperJournalStore? activeStore;
    PaperJournalController? journal;
    try {
      // First app session: write a deposit and a practice trade using the
      // Android sqflite plugin, never a fake desktop database.
      activeStore = SqlitePaperJournalStore(databasePath: databasePath);
      journal = PaperJournalController(store: activeStore);
      await journal.useAccount('101');
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await journal.add(LedgerEntry(
        id: 0, accountKey: journal.accountKey, kind: LedgerKind.deposit,
        timestampMs: now - 120000, amount: 1000,
      ));
      await journal.add(LedgerEntry(
        id: 0, accountKey: journal.accountKey, kind: LedgerKind.openTrade,
        timestampMs: now - 60000, openedAtMs: now - 60000,
        symbol: 'XAUUSD', side: PaperSide.buy,
        quantity: 2, entryPrice: 2000,
      ));

      // Test the real app shell and navigate to its Results tab.
      await tester.pumpWidget(TradeLabApp(controller: market, journal: journal));
      await tester.pumpAndSettle();
      await tester.tap(find.text('النتائج').last);
      await tester.pumpAndSettle();
      expect(find.text('المراكز التجريبية المفتوحة'), findsOneWidget);
      expect(find.text('إغلاق تجريبي'), findsOneWidget);
      expect(calculateLedgerReport(journal.entries).tradeCount, 0);

      final position = journal.entries.singleWhere(
          (entry) => entry.kind == LedgerKind.openTrade);
      await journal.closeTrade(position,
        exitPrice: 2020, timestampMs: now);
      await tester.pumpAndSettle();
      expect(calculateLedgerReport(journal.entries).netProfit, 40);
      expect(find.textContaining('+40.00 USD'), findsWidgets);

      // Simulate the application's state being torn down, release the native
      // SQLite connection, and create a new controller + storage handle.
      await tester.pumpWidget(const SizedBox.shrink());
      await activeStore.close();
      journal.dispose();
      activeStore = null;
      journal = null;

      activeStore = SqlitePaperJournalStore(databasePath: databasePath);
      journal = PaperJournalController(store: activeStore);
      await journal.useAccount('101');
      expect(journal.entries, hasLength(2));
      expect(calculateLedgerReport(journal.entries).netProfit, 40);
      final closed = journal.entries.singleWhere(
          (entry) => entry.kind == LedgerKind.closedTrade);
      expect(closed.exitPrice, 2020);
      expect(closed.openedAtMs, now - 60000);

      await tester.pumpWidget(TradeLabApp(controller: market, journal: journal));
      await tester.pumpAndSettle();
      await tester.tap(find.text('النتائج').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('+40.00 USD'), findsWidgets);

      // Account isolation: no other broker account may inherit saved P&L.
      await journal.useAccount('202');
      await tester.pumpAndSettle();
      expect(journal.entries, isEmpty);
      expect(find.textContaining('+40.00 USD'), findsNothing);
      await journal.useAccount('101');
      await tester.pumpAndSettle();
      expect(calculateLedgerReport(journal.entries).netProfit, 40);
      expect(find.textContaining('+40.00 USD'), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      // The only file removed is the unique Android smoke-test database.
      // Detach widgets before closing plugins that the shell may reference.
      await tester.pumpWidget(const SizedBox.shrink());
      if (activeStore != null) await activeStore.close();
      journal?.dispose();
      market.dispose();
      await deleteDatabase(databasePath);
    }
  });
}
