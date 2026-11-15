import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/replay/replay_training_order_dialog.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';

void main() {
  testWidgets('practice ticket validates inputs and owns its controllers',
      (tester) async {
    ReplayPracticeOrder? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<ReplayPracticeOrder>(
              context: context,
              builder: (_) => const ReplayTrainingOrderDialog(entryPrice: 100),
            );
          },
          child: const Text('Open training ticket'),
        )),
      ),
    ));
    await tester.tap(find.text('Open training ticket'));
    await tester.pumpAndSettle();
    expect(find.text('صفقة تدريب داخل Replay'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('replay-trade-quantity')), '0');
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await tester.pump();
    expect(find.textContaining('موجبة وصحيحة'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
        find.byKey(const Key('replay-trade-quantity')), '2');
    await tester.enterText(find.byKey(const Key('replay-trade-stop')), '95');
    await tester.enterText(find.byKey(const Key('replay-trade-target')), '110');
    await tester.ensureVisible(find.byKey(const Key('replay-trade-confirm')));
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.side, ReplaySide.buy);
    expect(result!.quantity, 2);
    expect(result!.stopLoss, 95);
    expect(result!.takeProfit, 110);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice stop must remain below buy entry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<ReplayPracticeOrder>(
            context: context,
            builder: (_) => const ReplayTrainingOrderDialog(entryPrice: 100),
          ),
          child: const Text('Enter trade'),
        )),
      ),
    ));
    await tester.tap(find.text('Enter trade'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('replay-trade-stop')), '105');
    await tester.tap(find.byKey(const Key('replay-trade-confirm')));
    await tester.pump();
    expect(find.textContaining('جهة الخسارة'), findsOneWidget);
  });
}
