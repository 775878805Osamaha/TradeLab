import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

/// The default chart exposes REAL, reachable controls in the constrained
/// phone header. This test requires no broker account or fabricated candles.
void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('mobile chart offers working candle preferences and move tools at $width dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 770));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(TradeLabApp(controller: market));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
      expect(find.byKey(const Key('chart-candle-settings-action')),
          findsOneWidget,
          reason: 'The prior inert numeric button has been replaced');
      expect(find.byKey(const Key('chart-move-mode')), findsOneWidget);
      expect(find.byKey(const Key('chart-zoom-in')), findsOneWidget);
      expect(find.byKey(const Key('chart-zoom-out')), findsOneWidget);
      expect(find.byKey(const Key('chart-back-to-live')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chart-candle-settings-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-symbol-settings-page')),
          findsOneWidget);
      expect(find.byKey(const Key('symbol-body-toggle')), findsOneWidget);
      await tester.tap(find.byKey(const Key('symbol-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget,
          reason: 'Direct preferences cancel must return to the chart, not a hidden panel');

      await tester.tap(find.byKey(const Key('chart-candle-settings-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('symbol-body-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('symbol-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
      expect(find.byKey(const Key('chart-symbol-settings-page')),
          findsNothing);

      await tester.tap(find.byKey(const Key('chart-move-mode')));
      await tester.tap(find.byKey(const Key('chart-zoom-in')));
      await tester.tap(find.byKey(const Key('chart-zoom-out')));
      await tester.tap(find.byKey(const Key('chart-back-to-live')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
