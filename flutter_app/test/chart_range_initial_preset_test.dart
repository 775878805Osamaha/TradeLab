import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

/// Checks the actual phone flow without making a broker request or inventing
/// BID ticks. Range bar generation remains owned by the authenticated feed.
void main() {
  testWidgets('Range starts with 25 BID points and preserves selectable 1000', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 770));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final market = MarketController();
    addTearDown(market.dispose);
    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chart-quick-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-quick-chart-type')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chart-type-bottom-sheet')), findsOneWidget);
    // The last grid row is initially clipped by the physical phone height.
    // Scroll the grid far enough to make the CENTER hit-testable, not merely
    // built by the lazy GridView.
    await tester.drag(find.byKey(const Key('chart-type-grid')),
        const Offset(0, -280));
    await tester.pumpAndSettle();
    final rangeCard = find.byKey(const Key('chart-kind-range'));
    expect(rangeCard, findsOneWidget);
    expect(tester.getCenter(rangeCard).dy, lessThan(760));
    await tester.tap(rangeCard);
    await tester.pumpAndSettle();

    expect(find.text('إعدادات شموع المدى'), findsOneWidget);
    final initial = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '25'));
    expect(initial.selected, isTrue,
        reason: '1000 points may create only one BID bar in a short authentic window');
    expect(tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1000')).selected, isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, '1000'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-quick-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-quick-range')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1000')).selected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
