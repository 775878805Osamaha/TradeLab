import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/main.dart';

/// A moving chart may repaint every frame, but must not rebuild the header,
/// account controls and tab layout on every pointer sample.
/// No broker data or fabricated market candles are needed to test this path.
void main() {
  testWidgets('ordinary chart pan repaints without rebuilding header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 770));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final market = MarketController();
    addTearDown(market.dispose);

    await tester.pumpWidget(TradeLabApp(controller: market));
    await tester.pumpAndSettle();
    final chart = find.byKey(const Key('chart-gesture-area'));
    final header = find.byKey(const Key('chart-reference-header'));
    expect(chart, findsOneWidget);
    expect(header, findsOneWidget);

    // The initial touch sets a one-time UI flag. Subsequent movement must
    // stay on the CustomPainter repaint fast path.
    await tester.drag(chart, const Offset(-70, 0));
    await tester.pumpAndSettle();
    final previousHeaderWidget = tester.widget(header);
    await tester.drag(chart, const Offset(-80, 0));
    // Drain GestureDetector's pending double-tap recognizer timeout before
    // the test binding checks for leaked timers after widget disposal.
    await tester.pump(const Duration(milliseconds: 400));

    expect(identical(previousHeaderWidget, tester.widget(header)), isTrue,
        reason: 'Gesture samples should repaint candles, not rebuild controls');
    expect(tester.takeException(), isNull);
  });
}
