import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

class _InMemoryJournal implements PaperJournalStore {
  final rows = <LedgerEntry>[];

  @override
  Future<List<LedgerEntry>> list(String accountKey) async => rows
      .where((e) => e.accountKey == accountKey).toList();

  @override
  Future<void> add(LedgerEntry entry) async {
    rows.add(entry);
  }

  @override
  Future<void> delete(String accountKey, int id) async {
    rows.removeWhere((e) => e.accountKey == accountKey && e.id == id);
  }

  @override
  Future<void> closeTrade(String accountKey, int id,
      {required double exitPrice, required int timestampMs}) async =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}
}

void main() {
  Future<void> phone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Lab is a separate tab and leaves Replay running in chart mode',
      (tester) async {
    await phone(tester);
    final store = _InMemoryJournal();
    final journal = PaperJournalController(store: store);
    addTearDown(journal.dispose);
    await journal.useAccount(null);
    final bars = List.generate(80, (index) {
      final openAt = 1700000000000 + index * 900000;
      return [openAt, '100', '101', '99', '100', '1', openAt + 899999];
    });
    final market = MarketController(api: MarketApi(client: MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      return http.Response(jsonEncode(bars), 200);
    })));
    addTearDown(market.dispose);
    await tester.pumpWidget(TradeLabApp(controller: market, journal: journal));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);

    // Playback pauses on navigation but the Replay session stays active.
    await tester.tap(find.byKey(const Key('replay-play-pause')));
    await tester.pump();
    expect(find.byTooltip('إيقاف'), findsOneWidget);

    await tester.tap(find.text('المختبر').last);
    await tester.pumpAndSettle();
    expect(find.text('مختبر التداول'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('lab-tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-tab-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('جلسة مجمدة · BTCUSDT'), findsOneWidget);
    expect(find.byKey(const Key('run-replay-analysis')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('lab-replay-observed-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-replay-observed-tab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lab-observed-stop')), '98');
    await tester.enterText(find.byKey(const Key('lab-observed-target')), '102');
    await tester.enterText(find.byKey(
      const Key('lab-observed-round-trip-cost')), '0.25');
    await tester.scrollUntilVisible(
      find.byKey(const Key('lab-record-observed-signal')), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-observed-trade')),
        matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const Key('lab-record-observed-signal')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('بانتظار شمعة الدخول'), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-observed-trade')),
        matching: find.byType(Scrollable)).first);
    expect(find.text('بانتظار شمعة الدخول'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('العودة للشارت وتقديم Replay'), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-observed-trade')),
        matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('العودة للشارت وتقديم Replay'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تقدم شمعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المختبر').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('مفتوحة افتراضيًا'), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-observed-trade')),
        matching: find.byType(Scrollable)).first);
    expect(find.text('مفتوحة افتراضيًا'), findsOneWidget,
      reason: 'the Lab must refresh its snapshot when revisited');
    await tester.scrollUntilVisible(find.text('R صافي تقديري غير محقق'), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-observed-trade')),
        matching: find.byType(Scrollable)).first);
    expect(find.text('R صافي تقديري غير محقق'), findsOneWidget,
      reason: 'an explicit cost estimate should survive Replay navigation');

    await tester.tap(find.text('الشارت').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget,
      reason: 'switching destinations must not reset the Replay cursor');
    expect(find.byTooltip('تشغيل'), findsOneWidget,
      reason: 'navigation should pause historical playback');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Risk Lab calculates from verified Binance bid/ask and local funds',
      (tester) async {
    await phone(tester);
    final store = _InMemoryJournal();
    final journal = PaperJournalController(store: store);
    addTearDown(journal.dispose);
    await journal.useAccount(null);
    await journal.add(LedgerEntry(id: 1, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000,
      amount: 100000));
    final market = MarketController(api: MarketApi(client: MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/ticker/bookTicker');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      return http.Response(jsonEncode({
        'symbol': 'BTCUSDT', 'bidPrice': '30000', 'askPrice': '30001',
      }), 200);
    })));
    addTearDown(market.dispose);
    await tester.pumpWidget(TradeLabApp(controller: market, journal: journal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المختبر').last);
    await tester.pumpAndSettle();
    expect(find.text('100000.00 USD'), findsWidgets);
    await tester.tap(find.byKey(const Key('lab-open-calculator')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-risk-symbol')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('BTCUSDT').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lab-stop-loss')), '29500');
    await tester.enterText(find.byKey(const Key('lab-take-profit')), '31000');
    await tester.enterText(find.byKey(const Key('lab-max-loss')), '100');
    await tester.ensureVisible(find.byKey(const Key('lab-calculate-risk')));
    await tester.tap(find.byKey(const Key('lab-calculate-risk')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('نتيجة الحساب'), 120,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-risk-calculator')),
        matching: find.byType(Scrollable)).first);
    await tester.pump();
    expect(find.text('نتيجة الحساب'), findsOneWidget);
    expect(find.text('الكمية القصوى بوحدات الأصل'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('30001.0'), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-risk-calculator')),
        matching: find.byType(Scrollable)).first);
    await tester.pump();
    expect(find.text('30001.0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab-tab-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-tab-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('lab-stop-loss')),
      -120, scrollable: find.descendant(
        of: find.byKey(const Key('lab-risk-calculator')),
        matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    final stopField = tester.widget<TextField>(find.byKey(
      const Key('lab-stop-loss')));
    expect(stopField.controller!.text, '29500',
      reason: 'switching sections should not erase calculator inputs');
    await tester.enterText(find.byKey(const Key('lab-stop-loss')), '29000');
    await tester.pump();
    expect(find.text('نتيجة الحساب'), findsNothing,
      reason: 'an edited plan invalidates the old quote calculation');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Replay tab offers a chart return when no verified session exists',
      (tester) async {
    await phone(tester);
    final journal = PaperJournalController(store: _InMemoryJournal());
    addTearDown(journal.dispose);
    await journal.useAccount(null);
    final market = MarketController();
    addTearDown(market.dispose);
    await tester.pumpWidget(TradeLabApp(controller: market, journal: journal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المختبر').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lab-tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('ابدأ Replay من الشارت'), findsOneWidget);
    await tester.tap(find.text('العودة للشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('advanced limits reject weak reward-risk and cap total notional',
      (tester) async {
    await phone(tester);
    final journal = PaperJournalController(store: _InMemoryJournal());
    addTearDown(journal.dispose);
    await journal.useAccount(null);
    await journal.add(LedgerEntry(id: 1, accountKey: journal.accountKey,
      kind: LedgerKind.deposit, timestampMs: 1700000000000,
      amount: 100000));
    final market = MarketController(api: MarketApi(client: MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/ticker/bookTicker');
      return http.Response(jsonEncode({
        'symbol': 'BTCUSDT', 'bidPrice': '30000', 'askPrice': '30001',
      }), 200);
    })));
    addTearDown(market.dispose);

    await tester.pumpWidget(TradeLabApp(controller: market, journal: journal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المختبر').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-risk-symbol')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('BTCUSDT').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lab-stop-loss')), '29500');
    await tester.enterText(find.byKey(const Key('lab-take-profit')), '31000');
    await tester.enterText(find.byKey(const Key('lab-max-loss')), '100');
    await tester.tap(find.text('حدود إضافية (اختيارية)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('lab-max-notional')));
    await tester.enterText(find.byKey(const Key('lab-max-notional')), '3000');
    await tester.ensureVisible(find.byKey(const Key('lab-max-trades')));
    await tester.enterText(find.byKey(const Key('lab-max-trades')), '2');
    await tester.ensureVisible(find.byKey(const Key('lab-min-reward-risk')));
    await tester.enterText(find.byKey(const Key('lab-min-reward-risk')), '3');
    await tester.ensureVisible(find.byKey(const Key('lab-calculate-risk')));
    await tester.tap(find.byKey(const Key('lab-calculate-risk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('نسبة العائد إلى المخاطرة أقل'), findsOneWidget);
    expect(find.text('نتيجة الحساب'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('lab-min-reward-risk')));
    await tester.enterText(find.byKey(const Key('lab-min-reward-risk')), '1');
    await tester.ensureVisible(find.byKey(const Key('lab-calculate-risk')));
    await tester.tap(find.byKey(const Key('lab-calculate-risk')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('0.099996'), 100,
      scrollable: find.descendant(
        of: find.byKey(const Key('lab-risk-calculator')),
        matching: find.byType(Scrollable)).first);
    expect(find.text('0.099996'), findsOneWidget,
      reason: '3000 USD notional / 30001 USD ask, rounded down to 6 places');

    await tester.ensureVisible(find.byKey(const Key('lab-max-trades')));
    await tester.enterText(find.byKey(const Key('lab-max-trades')), '2.5');
    await tester.ensureVisible(find.byKey(const Key('lab-calculate-risk')));
    await tester.tap(find.byKey(const Key('lab-calculate-risk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('عددًا صحيحًا موجبًا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
