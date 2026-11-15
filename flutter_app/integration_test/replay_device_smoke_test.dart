import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tradelab_flutter/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android chart never fabricates cTrader candles or opens Replay',
      (tester) async {
    await tester.pumpWidget(const TradeLabApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-practice-order')), findsNothing);
    expect(find.byKey(const Key('chart-source-empty')), findsOneWidget);
  });
}
