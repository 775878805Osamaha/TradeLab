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
}
