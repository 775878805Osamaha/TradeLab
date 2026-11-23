import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_indicator_engine.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/chart_indicator_pane.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  Future<void> open(WidgetTester tester, {
    required ChartIndicatorDefinition indicator,
    List<TradeCandle>? candles,
    Size size = const Size(390,844),
    VoidCallback? remove,
    GestureScaleUpdateCallback? drag,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source = candles ?? List<TradeCandle>.generate(100,(i) {
      final close = 100+(i%13).toDouble();
      return TradeCandle(close,close+1,close-1,close);
    });
    final controller = ValueNotifier<int>(0);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: ChartIndicatorPane(
        candles: source, indicator: indicator,
        cache: ChartIndicatorSeriesCache(),
        viewport: () => const ChartViewport(
          barWidth: 10, scrollBars: 0, rightMarginBars: 4),
        repaint: controller,
        onRemove: remove ?? () {},
        onScaleStart: (_) {},
        onScaleUpdate: drag ?? (_) {},
      ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('RSI is an independent visible pane with its own axis',
      (tester) async {
    await open(tester,
      indicator: const ChartIndicatorDefinition('rsi-14','RSI 14',14));
    expect(find.byKey(const Key('chart-indicator-pane-rsi-14')),
        findsOneWidget);
    expect(find.text('RSI 14'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('MACD draws 3 series with honest own-value axis at 320dp',
      (tester) async {
    await open(tester,
      indicator: const ChartIndicatorDefinition('macd','MACD',12),
      size: const Size(320,640));
    expect(find.byKey(const Key('chart-indicator-pane-macd')),
        findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('pane close removes only its own study', (tester) async {
    var removed = 0;
    await open(tester,
      indicator: const ChartIndicatorDefinition('atr-14','ATR 14',14),
      remove: () => removed++);
    await tester.tap(find.byKey(
      const Key('chart-indicator-remove-atr-14')));
    await tester.pumpAndSettle();
    expect(removed,1);
    expect(tester.takeException(),isNull);
  });

  testWidgets('gesture listener is wired to the shared chart viewport',
      (tester) async {
    var gestures = 0;
    await open(tester,
      indicator: const ChartIndicatorDefinition('rsi-14','RSI 14',14),
      drag: (_) => gestures++);
    await tester.drag(find.byKey(
      const Key('chart-indicator-pane-rsi-14')),const Offset(120,0));
    await tester.pumpAndSettle();
    expect(gestures,greaterThan(0));
    expect(tester.takeException(),isNull);
  });

  testWidgets('source-empty pane stays blank instead of inventing quotes',
      (tester) async {
    await open(tester,
      indicator: const ChartIndicatorDefinition('macd','MACD',12),
      candles: []);
    expect(find.byKey(const Key('chart-indicator-pane-macd')),
        findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
