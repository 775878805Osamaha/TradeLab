import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_analysis_sheet.dart';

void main() {
  testWidgets('editing an assumption invalidates an old Replay simulation',
      (tester) async {
    final start = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;
    final bars = List<MarketBar>.generate(40, (i) => MarketBar(
      start + i * 60000, const TradeCandle(100, 101, 99, 100)));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ReplayAnalysisSheet(bars: bars, symbol: 'XAUUSD', timeframe: '1m'))));
    await tester.enterText(find.byType(TextField).at(0), '99.5');
    await tester.enterText(find.byType(TextField).at(1), '100.5');
    await tester.enterText(find.byKey(const Key('replay-scenario-round-trip-cost')),
      '0.2');
    await tester.tap(find.byKey(const Key('run-replay-analysis')));
    await tester.pump();
    expect(find.textContaining('الهدف أولًا'), findsOneWidget);
    expect(find.textContaining('الصافي التقديري'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '98');
    await tester.pump();
    expect(find.textContaining('الهدف أولًا'), findsNothing);
    expect(find.textContaining('الصافي التقديري'), findsNothing);
    await tester.enterText(find.byKey(const Key('replay-scenario-round-trip-cost')),
      '-1');
    await tester.tap(find.byKey(const Key('run-replay-analysis')));
    await tester.pump();
    expect(find.textContaining('يجب ألا تكون سالبة'), findsOneWidget);
  });
}
