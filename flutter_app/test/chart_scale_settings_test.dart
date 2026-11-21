import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_axis_source_labels.dart';
import 'package:tradelab_flutter/chart/chart_scale_settings.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/chart/chart_scale_settings_page.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('PROMPT 13 reference values and local preference codec', () {
    const initial = ChartScaleSettings();
    expect(initial.previousClose, ChartPriceLabelMode.hidden);
    expect(initial.indicatorLabels, ChartPriceLabelMode.value);
    expect(initial.highLow, ChartPriceLabelMode.hidden);
    expect(initial.bidAsk, ChartPriceLabelMode.hidden);
    expect(initial.weekdayOnLabels, isTrue);
    expect(initial.askColor, 0xFFF49EA8);
    expect(initial.bidColor, 0xFF88A3F8);
    expect(initial.symbolLabelPlacement, 'القيمة حسب المقياس');
    final altered = initial.copyWith(
      previousClose: ChartPriceLabelMode.valueAndLine,
      highLow: ChartPriceLabelMode.value,
      bidAsk: ChartPriceLabelMode.value,
      weekdayOnLabels: false,
      askColor: 0xFF112233,
    );
    final restored = ChartScaleSettings.decode(altered.encode());
    expect(restored.previousClose, ChartPriceLabelMode.valueAndLine);
    expect(restored.highLow, ChartPriceLabelMode.value);
    expect(restored.bidAsk, ChartPriceLabelMode.value);
    expect(restored.weekdayOnLabels, isFalse);
    expect(restored.askColor, 0xFF112233);
    expect(initial.previousClose, ChartPriceLabelMode.hidden);
    expect(ChartScaleSettings.decode('{}').weekdayOnLabels, isTrue);
    expect(ChartScaleSettings.decode('{"bidAsk":"unexpected"}').bidAsk,
      ChartPriceLabelMode.hidden);
  });

  test('New York weekday follows displayed date, not phone timezone', () {
    // UTC Thursday morning is still Wednesday evening in New York.
    final winterUtc = DateTime.utc(2026, 11, 19, 2, 30)
        .millisecondsSinceEpoch;
    final utc = ChartTimeZone.utc.displayDate(winterUtc);
    final ny = ChartTimeZone.newYork.displayDate(winterUtc);
    expect(utc.day, 19);
    expect(ny.day, 18);
    expect(ChartScaleSettings.weekdayForDisplayedDate(utc), 'الخميس');
    expect(ChartScaleSettings.weekdayForDisplayedDate(ny), 'الأربعاء');

    // The same offset difference applies during US daylight saving time,
    // when New York is UTC-4 rather than the winter UTC-5.
    final summerUtc = DateTime.utc(2026, 7, 15, 2, 30)
        .millisecondsSinceEpoch;
    expect(ChartScaleSettings.weekdayForDisplayedDate(
        ChartTimeZone.utc.displayDate(summerUtc)), 'الأربعاء');
    expect(ChartScaleSettings.weekdayForDisplayedDate(
        ChartTimeZone.newYork.displayDate(summerUtc)), 'الثلاثاء');

    // Device mode has already been converted by displayDate. The calendar
    // weekday must match the actual date presented on that device.
    final device = ChartTimeZone.device.displayDate(winterUtc);
    expect(ChartScaleSettings.weekdayForDisplayedDate(device),
        ChartScaleSettings.weekdays[device.weekday - 1]);
  });

  test('previous close uses provider bars in the visible replay prefix only', () {
    const candle1 = TradeCandle(100, 105, 95, 102);
    const candle2 = TradeCandle(102, 108, 101, 107);
    const candle3 = TradeCandle(107, 110, 106, 109);
    final bars = <MarketBar>[
      MarketBar(DateTime.utc(2026, 11, 9, 23).millisecondsSinceEpoch, candle1),
      MarketBar(DateTime.utc(2026, 11, 10, 0).millisecondsSinceEpoch, candle2),
      MarketBar(DateTime.utc(2026, 11, 11, 0).millisecondsSinceEpoch, candle3),
    ];
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 1), isNull);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 2), 102);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 3), 107);
    expect(ChartAxisSourceLabels.previousSessionClose([], 0), isNull);
    final extremes = ChartAxisSourceLabels.visibleHighLow(
      [candle1, candle2, candle3], 0, 2);
    expect(extremes, (108.0, 95.0));
    expect(ChartAxisSourceLabels.visibleHighLow([], 0, 0), isNull);
  });

  Future<void> mount(WidgetTester tester, {
    required ValueChanged<ChartScaleSettings> onApply,
    required VoidCallback onCancel,
    ChartScaleSettings initial = const ChartScaleSettings(),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SafeArea(child: Directionality(
          textDirection: TextDirection.rtl,
          child: ChartScaleSettingsPage(
            initial: initial, onApply: onApply, onCancel: onCancel),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('inverted price scale checkbox commits true and round trips',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartScaleSettings? committed;
    await mount(tester, onApply: (v) => committed = v,
        onCancel: () {});
    final checkbox = find.byKey(const Key('scale-inverted'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scale-apply')));
    await tester.pumpAndSettle();
    expect(committed?.inverted, isTrue);
    expect(ChartScaleSettings.decode(committed!.encode()).inverted, isTrue);
  });

  for (final mode in <String>['نسبة مئوية', 'مؤشر 100']) {
    testWidgets('percent/indexed scale $mode selects and saves a real mode',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 872));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ChartScaleSettings? committed;
      await mount(tester, onApply: (v) => committed = v,
          onCancel: () {});
      final popup = find.byKey(const Key('scale-mode'));
      await tester.ensureVisible(popup);
      await tester.tap(popup);
      await tester.pumpAndSettle();
      expect(find.text(mode), findsOneWidget);
      await tester.tap(find.text(mode).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-apply')));
      await tester.pumpAndSettle();
      expect(committed?.scaleMode, mode);
      expect(ChartScaleSettings.decode(committed!.encode()).scaleMode, mode);
    });
  }

  testWidgets('real logarithmic price-scale mode is selectable and saved',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartScaleSettings? applied;
    await mount(tester, onApply: (value) => applied = value,
        onCancel: () {});
    final dropdown = find.byKey(const Key('scale-mode'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('لوغاريتمي'), findsOneWidget);
    await tester.tap(find.text('لوغاريتمي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scale-apply')));
    await tester.pumpAndSettle();
    expect(applied, isNotNull);
    expect(applied!.scaleMode, 'لوغاريتمي');
    expect(ChartScaleSettings.decode(applied!.encode()).scaleMode,
        'لوغاريتمي');
  });

  testWidgets('footer stays fixed while the full lower reference is scrolled',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester, onApply: (_) {}, onCancel: () {});
    final footerBefore = tester.getTopLeft(
      find.byKey(const Key('scale-fixed-footer')));
    await tester.drag(find.byKey(const Key('scale-settings-scroll')),
      const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('scale-fixed-footer'))),
      footerBefore);
    expect(find.text('إغلاق اليوم السابق'), findsOneWidget);
    expect(find.text('المؤشرات والبيانات المالية'), findsOneWidget);
    expect(find.text('أعلى وأدنى'), findsOneWidget);
    expect(find.text('سعر البيع والشراء'), findsOneWidget);
    expect(find.text('مقياس الوقت'), findsOneWidget);
    expect(find.text('يوم الأسبوع على الملصقات'), findsOneWidget);
    expect(find.byKey(const Key('scale-weekday')), findsOneWidget);
    expect(find.byKey(const Key('scale-apply')), findsOneWidget);
  });

  testWidgets('toggling weekday then cancel never commits the change',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartScaleSettings? committed;
    var cancelled = 0;
    await mount(tester, onApply: (value) => committed = value,
      onCancel: () => cancelled++);
    await tester.ensureVisible(find.byKey(const Key('scale-weekday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scale-weekday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scale-cancel')));
    expect(cancelled, 1);
    expect(committed, isNull);
  });

  testWidgets('the reference weekday selection is editable and applies',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartScaleSettings? committed;
    await mount(tester, onApply: (value) => committed = value,
      onCancel: () {});
    await tester.ensureVisible(find.byKey(const Key('scale-weekday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scale-weekday')));
    await tester.pump();
    expect(committed, isNull);
    await tester.tap(find.byKey(const Key('scale-apply')));
    expect(committed?.weekdayOnLabels, isFalse);
    expect(committed?.previousClose, ChartPriceLabelMode.hidden);
    expect(committed?.bidAsk, ChartPriceLabelMode.hidden);
  });

  testWidgets('hidden line previews do not open an interactive color palette',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mount(tester, onApply: (_) {}, onCancel: () {});
    await tester.ensureVisible(find.byKey(const Key('scale-previous-close-color')));
    await tester.pumpAndSettle();
    expect(tester.widget<GestureDetector>(
      find.byKey(const Key('scale-previous-close-color'))).onTap, isNull);
    expect(tester.widget<GestureDetector>(
      find.byKey(const Key('scale-high-low-colors'))).onTap, isNull);
    expect(tester.widget<GestureDetector>(
      find.byKey(const Key('scale-bid-color'))).onTap, isNull);
  });
}
