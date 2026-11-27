import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';
import 'package:tradelab_flutter/screens/chart_screen.dart';

/// Focus mode is purely a layout change. It never changes the chart State,
/// source candles, Replay cursor, saved drawings or account sandbox.
void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('chart focus expands plot and restores navigation at $width dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 770));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(TradeLabApp(controller: market));
      await tester.pumpAndSettle();

      final chart = find.byKey(const Key('chart-gesture-area'));
      final originalState = tester.state(find.byType(ChartScreen));
      final originalHeight = tester.getSize(chart).height;
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const Key('chart-reference-toolbar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chart-quick-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chart-quick-focus')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chart-focus-header')), findsOneWidget);
      expect(find.byKey(const Key('chart-focus-exit')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('chart-reference-toolbar')), findsNothing);
      expect(tester.getSize(chart).height, greaterThan(originalHeight + 80));
      expect(identical(originalState, tester.state(find.byType(ChartScreen))),
          isTrue, reason: 'focus must never recreate the trading chart');

      await tester.tap(find.byKey(const Key('chart-focus-exit')));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const Key('chart-reference-toolbar')), findsOneWidget);
      expect(find.byKey(const Key('chart-focus-header')), findsNothing);
      expect(identical(originalState, tester.state(find.byType(ChartScreen))),
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system back exits chart focus instead of losing the session',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 770));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final market = MarketController();
    addTearDown(market.dispose);
    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();
    final originalState = tester.state(find.byType(ChartScreen));

    await tester.tap(find.byKey(const Key('chart-quick-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chart-quick-focus')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('chart-focus-header')), findsNothing);
    expect(identical(originalState, tester.state(find.byType(ChartScreen))),
        isTrue);
    expect(tester.takeException(), isNull);
  });
}
