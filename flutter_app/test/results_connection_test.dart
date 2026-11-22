import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/results_screen.dart';

class _ConnectedReadOnlyController extends MarketController {
  @override
  bool get ctraderConnected => true;
}

void main() {
  testWidgets('a linked cTrader account is not reported as disconnected',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.reset);
    final controller = _ConnectedReadOnlyController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ResultsScreen(controller: controller)),
    ));
    await tester.pump();
    expect(find.text('cTrader متصل'), findsOneWidget);
    expect(find.text('لا توجد حسابات متصلة'), findsNothing);
    expect(find.textContaining('لن نعرض أرصدة أو أرباحًا مفترضة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('Replay archive shows opened and closed training upon tab return',
      (tester) async {
    final controller = _ConnectedReadOnlyController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reads = 0;
    Future<List<Map<String, Object?>>> load() async {
      reads++;
      return [<String, Object?>{
        'sessionId': 'session-visible',
        'sourceKey': 'never-show-account-id',
        'savedAtMs': 1795262400000,
        'tradeCount': 2,
        'openTradeCount': 1,
        'closedTradeCount': 1,
        'realizedPricePnl': 17.5,
        'trades': [
          <String, Object?>{
            'side': 'buy', 'entryPrice': 100.0, 'quantity': 1.0,
            'exitPrice': null, 'isOpen': true, 'realizedPricePnl': 0.0,
          },
          <String, Object?>{
            'side': 'sell', 'entryPrice': 110.0, 'quantity': 2.0,
            'exitPrice': 101.25, 'isOpen': false, 'realizedPricePnl': 17.5,
          },
        ],
      }];
    }
    Future<void> show(bool active) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ResultsScreen(controller: controller,
        active: active, replayArchiveReader: load)),
    ));
    await show(false);
    expect(reads, 0);
    await show(true);
    await tester.pump();
    expect(reads, 1);
    await tester.ensureVisible(find.byKey(const Key('results-tab-5')));
    await tester.tap(find.byKey(const Key('results-tab-5')));
    await tester.pump();
    expect(find.byKey(const Key('results-replay-session-0')), findsOneWidget);
    expect(find.text('الصفقات: 2 · مفتوحة: 1 · مغلقة: 1'), findsOneWidget);
    expect(find.textContaining('17.5000'), findsWidgets);
    expect(find.textContaining('ليست أرباحًا بالدولار'), findsOneWidget);
    expect(find.byKey(const Key('results-replay-trade-0-1')), findsOneWidget);
    expect(find.byKey(const Key('results-replay-trade-0-0')), findsOneWidget);
    expect(find.textContaining('بيع · مغلقة'), findsOneWidget);
    expect(find.textContaining('شراء · مفتوحة'), findsOneWidget);
    expect(find.textContaining('دخول: 110.00000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('never-show-account-id'), findsNothing);
    await show(false);
    await show(true);
    await tester.pump();
    expect(reads, 2);
  });

  testWidgets('Replay archive read failure is not displayed as no trades',
      (tester) async {
    final controller = _ConnectedReadOnlyController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<List<Map<String, Object?>>> failed() async =>
        throw StateError('SQLite unavailable');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ResultsScreen(controller: controller,
        active: true, replayArchiveReader: failed)),
    ));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('results-tab-5')));
    await tester.tap(find.byKey(const Key('results-tab-5')));
    await tester.pump();
    expect(find.byKey(const Key('results-replay-error')), findsOneWidget);
    expect(find.textContaining('لا توجد جلسات Replay محفوظة بعد'), findsNothing);
  });

  testWidgets('Overview links to actual Replay open/closed counts at 320dp',
      (tester) async {
    final controller = _ConnectedReadOnlyController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<List<Map<String, Object?>>> read() async => [
      <String, Object?>{
        'sessionId': 'internal-not-visible',
        'sourceKey': 'account-hidden',
        'savedAtMs': 1795262400000,
        'tradeCount': 2,
        'openTradeCount': 1,
        'closedTradeCount': 1,
        'realizedPricePnl': 12.5,
      },
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ResultsScreen(controller: controller,
          active: true, replayArchiveReader: read)),
    ));
    await tester.pump();
    final shortcut = find.byKey(
        const Key('results-replay-overview-shortcut'));
    expect(shortcut, findsOneWidget);
    expect(find.textContaining('مفتوحة: 1 · مغلقة: 1'), findsOneWidget);
    // The normal USD hero still reads only the separate paper ledger.
    expect(find.byKey(const Key('results-net-profit-hero')), findsOneWidget);
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await tester.pump();
    expect(find.byKey(const Key('results-replay-session-0')), findsOneWidget);
    expect(find.textContaining('12.5000'), findsOneWidget);
    expect(find.textContaining('account-hidden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Replay rows reveal older positions in bounded pages at 320dp',
      (tester) async {
    final controller = _ConnectedReadOnlyController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<List<Map<String, Object?>>> read() async => [
      <String, Object?>{
        'sessionId': 'many-entries',
        'savedAtMs': 1795262400000,
        'tradeCount': 25,
        'openTradeCount': 25,
        'closedTradeCount': 0,
        'realizedPricePnl': 0.0,
        'trades': List<Map<String, Object?>>.generate(25, (index) => {
          'side': 'buy',
          'entryPrice': 100.0 + index,
          'quantity': 1.0,
          'exitPrice': null,
          'isOpen': true,
          'realizedPricePnl': 0.0,
        }),
      },
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ResultsScreen(controller: controller,
          active: true, replayArchiveReader: read),
    )));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('results-tab-5')));
    await tester.tap(find.byKey(const Key('results-tab-5')));
    await tester.pump();
    expect(find.byKey(const Key('results-replay-trade-0-24')), findsOneWidget);
    expect(find.byKey(const Key('results-replay-trade-0-21')), findsNothing);
    final more = find.byKey(const Key('results-replay-more-trades-0'));
    // The results tab has a sticky header; ensureVisible may put a
    // TextButton center exactly on the bottom test-view boundary (y=760),
    // where a pointer tap misses. Scroll a little farther before tapping.
    await tester.ensureVisible(more);
    await tester.pump();
    await tester.drag(find.byKey(const Key('results-dashboard-list')),
        const Offset(0, -90));
    await tester.pump();
    await tester.tap(more);
    await tester.pump();
    expect(find.byKey(const Key('results-replay-trade-0-21')), findsOneWidget);
    expect(find.byKey(const Key('results-replay-trade-0-0')), findsNothing);
    await tester.ensureVisible(more);
    await tester.pump();
    await tester.drag(find.byKey(const Key('results-dashboard-list')),
        const Offset(0, -90));
    await tester.pump();
    await tester.tap(more);
    await tester.pump();
    expect(find.byKey(const Key('results-replay-trade-0-0')), findsOneWidget);
    expect(find.byKey(const Key('results-replay-more-trades-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
