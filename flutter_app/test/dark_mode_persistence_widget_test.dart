import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/theme_preference_store.dart';
import 'package:tradelab_flutter/main.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

class _EmptyLedgerStore implements PaperJournalStore {
  @override
  Future<List<LedgerEntry>> list(String key) async => const [];
  @override
  Future<void> add(LedgerEntry entry) async {}
  @override
  Future<void> closeTrade(String key, int id,
      {required double exitPrice, required int timestampMs}) async {}
  @override
  Future<void> delete(String key, int id) async {}
  @override
  Future<void> close() async {}
}

class _MemoryThemeStore implements ThemePreferenceStore {
  _MemoryThemeStore(this.value);
  bool? value;
  int writes = 0;

  @override
  Future<bool?> loadDarkMode() async => value;
  @override
  Future<void> saveDarkMode(bool enabled) async {
    value = enabled;
    writes++;
  }
}

class _DeferredThemeStore implements ThemePreferenceStore {
  final pending = Completer<bool?>();
  bool? lastSaved;
  @override
  Future<bool?> loadDarkMode() => pending.future;
  @override
  Future<void> saveDarkMode(bool enabled) async => lastSaved = enabled;
}

Future<void> openAccount(WidgetTester tester) async {
  await tester.tap(find.text('الحساب').last);
  await tester.pumpAndSettle();
  final list = find.byKey(const Key('account-dashboard-list'));
  await tester.scrollUntilVisible(
    find.byKey(const Key('dark-mode-switch')), 220,
    scrollable: find.descendant(
        of: list, matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('dark preference is restored after app restart at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      final journal = PaperJournalController(store: _EmptyLedgerStore());
      addTearDown(market.dispose);
      addTearDown(journal.dispose);
      final store = _MemoryThemeStore(true);

      Widget app() => TradeLabApp(
        controller: market, journal: journal, themeStore: store);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark);
      await openAccount(tester);
      final switcher = find.byKey(const Key('dark-mode-switch'));
      expect(tester.widget<SwitchListTile>(switcher).value, isTrue);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(store.value, isFalse);
      expect(store.writes, 1);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.light);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.light);
      expect(store.writes, 1,
          reason: 'Restoring the saved preference must not rewrite it');
      expect(tester.takeException(), isNull);
    });

    testWidgets('late stored preference cannot override user switch '
        'at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      final journal = PaperJournalController(store: _EmptyLedgerStore());
      addTearDown(market.dispose);
      addTearDown(journal.dispose);
      final store = _DeferredThemeStore();
      await tester.pumpWidget(TradeLabApp(
        controller: market, journal: journal, themeStore: store));
      await tester.pumpAndSettle();
      await openAccount(tester);
      final switcher = find.byKey(const Key('dark-mode-switch'));
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark);
      // The storage read was started before the user switched themes.
      store.pending.complete(false);
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark);
      expect(store.lastSaved, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
