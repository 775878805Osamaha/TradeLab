import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_panel_settings.dart';
import 'package:tradelab_flutter/chart/chart_panel_settings_page.dart';
import 'package:tradelab_flutter/chart/chart_viewport.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('settings serialize without any market candle state', () {
    const defaults = ChartPanelSettings();
    final edited = defaults.copyWith(axisTextSize: 16,
      topMarginPercent: 14, bottomMarginPercent: 12,
      rightMarginBars: 20,
      navigationButtons: ChartButtonVisibility.hidden);
    final restored = ChartPanelSettings.decode(edited.encode());
    expect(restored.axisTextSize, 16);
    expect(restored.topMarginPercent, 14);
    expect(restored.bottomMarginPercent, 12);
    expect(restored.rightMarginBars, 20);
    expect(restored.navigationButtons, ChartButtonVisibility.hidden);
    expect(defaults.axisTextSize, 12);
    expect(defaults.rightMarginBars, 10);
    expect(ChartPanelSettings.marginsValid(51, 30, 10), isFalse);
  });

  test('margins alter chart coordinate space, not the market candles', () {
    final candles = List<TradeCandle>.generate(50, (i) =>
      TradeCandle(100 + i.toDouble(), 101 + i.toDouble(),
        99 + i.toDouble(), 100.5 + i.toDouble()));
    const base = ChartViewport(barWidth: 10, rightMarginBars: 10);
    final original = List<TradeCandle>.of(candles);
    final increased = ChartPriceScale.visible(candles, base,
      300, 400, topMarginPercent: 20, bottomMarginPercent: 16);
    final defaultScale = ChartPriceScale.visible(candles, base,
      300, 400, topMarginPercent: 10, bottomMarginPercent: 8);
    expect(increased.maximum, greaterThan(defaultScale.maximum));
    expect(increased.minimum, lessThan(defaultScale.minimum));
    expect(base.chartX(index: 49, candleCount: 50, plotWidth: 300),
      closeTo(195, .00001));
    final changed = base.withRightMarginBars(20);
    expect(changed.chartX(index: 49, candleCount: 50, plotWidth: 300),
      closeTo(95, .00001));
    expect(changed.indexAt(x: 95, plotWidth: 300, candleCount: 50), 49);
    expect(base.rightMarginBars, 10);
    expect(candles, orderedEquals(original));
  });

  Future<void> mount(WidgetTester tester, {
    required ValueChanged<ChartPanelSettings> onApply,
    required VoidCallback onCancel,
    ChartPanelSettings initial = const ChartPanelSettings(),
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      home: Scaffold(body: SafeArea(child: Directionality(
        textDirection: TextDirection.rtl,
        child: ChartPanelSettingsPage(initial: initial,
          onApply: onApply, onCancel: onCancel),
      ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('fixed footer persists while only form scrolls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester, onApply: (_) {}, onCancel: () {});
    expect(find.byKey(const Key('panel-fixed-footer')), findsOneWidget);
    expect(find.byKey(const Key('panel-apply')), findsOneWidget);
    await tester.drag(find.byKey(const Key('panel-settings-scroll')),
      const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('هوامش'), findsOneWidget);
    expect(find.byKey(const Key('panel-margin-top')), findsOneWidget);
    expect(find.byKey(const Key('panel-fixed-footer')), findsOneWidget);
  });

  testWidgets('Cancel discards edits, Apply returns typed margins', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartPanelSettings? saved;
    var canceled = 0;
    await mount(tester, onApply: (s) => saved = s,
      onCancel: () => canceled++);
    await tester.drag(find.byKey(const Key('panel-settings-scroll')),
      const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('panel-margin-top')), '18');
    await tester.tap(find.byKey(const Key('panel-cancel')));
    expect(canceled, 1);
    expect(saved, isNull);
    await mount(tester, onApply: (s) => saved = s,
      onCancel: () => canceled++);
    await tester.drag(find.byKey(const Key('panel-settings-scroll')),
      const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('panel-margin-top')), '18');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('panel-apply')));
    expect(saved?.topMarginPercent, 18);
    expect(saved?.bottomMarginPercent, 8);
    expect(saved?.rightMarginBars, 10);
  });
}
