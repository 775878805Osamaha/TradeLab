import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_lab_bridge.dart';
import 'package:tradelab_flutter/replay/replay_research_workspace.dart';

void main() {
  testWidgets('Replay journal records an observed signal and confirms clearing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final start = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
    final bars = List.generate(40, (i) => MarketBar(start + i * 60000,
      const TradeCandle(100, 100, 100, 100)));
    final snapshot = ReplayLabSnapshot(accountKey: 'local:guest',
      symbol: 'BTCUSDT', timeframe: '1m', bars: List.unmodifiable(bars));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ReplayResearchWorkspace(snapshot: snapshot, onOpenChart: () {}))));

    await tester.ensureVisible(find.byKey(const Key('lab-replay-observed-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-replay-observed-tab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lab-observed-stop')), '99');
    await tester.enterText(find.byKey(const Key('lab-observed-target')), '103');
    await tester.ensureVisible(find.byKey(const Key('lab-record-observed-signal')));
    await tester.tap(find.byKey(const Key('lab-record-observed-signal')));
    await tester.pumpAndSettle();
    expect(find.text('بانتظار شمعة الدخول'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('lab-replay-session-tab')));
    await tester.tap(find.byKey(const Key('lab-replay-session-tab')));
    await tester.pumpAndSettle();
    expect(find.text('سجل الجلسة التدريبية'), findsOneWidget);
    expect(find.text('1 / 0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replay-session-clear')));
    await tester.pumpAndSettle();
    expect(find.text('مسح سجل Replay؟'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 0'), findsOneWidget,
      reason: 'cancelling clear must preserve research signals');

    await tester.tap(find.byKey(const Key('replay-session-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مسح الإشارات'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد إشارات مسجلة في هذه الجلسة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
