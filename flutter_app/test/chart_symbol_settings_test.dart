import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings.dart';
import 'package:tradelab_flutter/chart/chart_symbol_settings_page.dart';

void main() {
  test('PROMPT 14 original defaults, independent colors and codec', () {
    const initial = ChartSymbolSettings();
    expect(initial.colorByPreviousClose, isTrue);
    expect(initial.bodyVisible, isTrue);
    expect(initial.borderVisible, isTrue);
    expect(initial.wickVisible, isTrue);
    expect(initial.bodyBull, 0xFF089981);
    expect(initial.bodyBear, 0xFFF23645);
    expect(initial.borderBull, 0xFF089981);
    expect(initial.borderBear, 0xFFF23645);
    expect(initial.wickBull, 0xFF089981);
    expect(initial.wickBear, 0xFFF23645);
    expect(initial.precisionDigits, isNull);
    expect(initial.timeZone, ChartTimeZone.newYork);

    final updated = initial.copyWith(
      bodyBear: 0xFF112233, borderBull: 0xFF445566,
      wickBear: 0xFF778899, wickVisible: false,
      timeZone: ChartTimeZone.utc).withPrecision(4);
    final restored = ChartSymbolSettings.decode(updated.encode());
    expect(restored.bodyBear, 0xFF112233);
    expect(restored.borderBull, 0xFF445566);
    expect(restored.wickBear, 0xFF778899);
    expect(restored.bodyBull, initial.bodyBull);
    expect(restored.borderBear, initial.borderBear);
    expect(restored.wickBull, initial.wickBull);
    expect(restored.wickVisible, isFalse);
    expect(restored.precisionDigits, 4);
    expect(restored.digitsForTickStep(2), 4);
    expect(restored.timeZone, ChartTimeZone.utc);
    expect(restored.withPrecision(null).digitsForTickStep(3), 3);
    expect(ChartSymbolSettings.decode('{}').bodyBull, initial.bodyBull);
    expect(ChartSymbolSettings.decode('malformed').timeZone,
      ChartTimeZone.newYork);
    expect(ChartSymbolSettings.decode('{"precisionDigits":999}').precisionDigits,
      isNull);
  });

  test('New York switches offsets at DST without moving source timestamps', () {
    final beforeSpring = DateTime.utc(2026, 3, 8, 6, 59);
    final afterSpring = DateTime.utc(2026, 3, 8, 7);
    final beforeFall = DateTime.utc(2026, 11, 1, 5, 59);
    final afterFall = DateTime.utc(2026, 11, 1, 6);
    expect(ChartTimeZone.newYorkOffset(beforeSpring).inHours, -5);
    expect(ChartTimeZone.newYorkOffset(afterSpring).inHours, -4);
    expect(ChartTimeZone.newYorkOffset(beforeFall).inHours, -4);
    expect(ChartTimeZone.newYorkOffset(afterFall).inHours, -5);
    final source = afterSpring.millisecondsSinceEpoch;
    final ny = ChartTimeZone.newYork.displayDate(source);
    expect((ny.hour, ny.minute), (3, 0));
    expect(ChartTimeZone.utc.displayDate(source), afterSpring);
    expect(afterSpring.millisecondsSinceEpoch, source);
    expect(ChartTimeZone.newYork.labelAt(DateTime.utc(2026, 7, 1)),
      'نيويورك (UTC-4)');
    expect(ChartTimeZone.newYork.labelAt(DateTime.utc(2026, 11, 11)),
      'نيويورك (UTC-5)');
  });

  Future<void> mount(WidgetTester tester, {
    required ValueChanged<ChartSymbolSettings> onApply,
    required VoidCallback onCancel,
    ChartSymbolSettings initial = const ChartSymbolSettings(),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(locale: const Locale('ar'),
      home: MediaQuery(data: MediaQueryData(
        textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SafeArea(child: Directionality(
          textDirection: TextDirection.rtl,
          child: ChartSymbolSettingsPage(initial: initial,
            onApply: onApply, onCancel: onCancel)))))));
    await tester.pump();
  }

  for (final width in [393.0, 320.0]) {
    testWidgets('reference geometry and checked controls on $width px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 872));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, onApply: (_) {}, onCancel: () {});
      expect(find.text('رمز'), findsOneWidget);
      expect(find.text('شموع'), findsOneWidget);
      expect(find.text('تعديل البيانات'), findsOneWidget);
      expect(find.byKey(const Key('symbol-body-bear')), findsOneWidget);
      expect(find.byKey(const Key('symbol-body-bull')), findsOneWidget);
      expect(find.byKey(const Key('symbol-border-bear')), findsOneWidget);
      expect(find.byKey(const Key('symbol-wick-bull')), findsOneWidget);
      expect(find.text('افتراضي'), findsOneWidget);
      expect(find.textContaining('نيويورك'), findsOneWidget);
      expect(find.byKey(const Key('symbol-fixed-footer')), findsOneWidget);
      expect(find.byKey(const Key('symbol-apply')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('symbol-fixed-footer'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('symbol-title'))).dy));
    });
  }

  testWidgets('checkbox and separate body color are drafts until apply',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartSymbolSettings? committed;
    await mount(tester, onApply: (s) => committed = s, onCancel: () {});
    await tester.tap(find.byKey(const Key('symbol-wick-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('symbol-body-bear')));
    // Wait for the modal's entrance animation before hitting its palette;
    // a single pump would leave palette taps below the test viewport.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-palette-ff2962ff')));
    await tester.pumpAndSettle();
    expect(committed, isNull);
    await tester.tap(find.byKey(const Key('symbol-apply')));
    expect(committed?.wickVisible, isFalse);
    expect(committed?.bodyBear, 0xFF2962FF);
    expect(committed?.borderBear, 0xFFF23645);
    expect(committed?.wickBear, 0xFFF23645);
  });

  testWidgets('cancel discards drafts and confirmation footer is fixed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartSymbolSettings? committed;
    var cancelled = 0;
    await mount(tester, onApply: (s) => committed = s,
      onCancel: () => cancelled++);
    final before = tester.getTopLeft(find.byKey(const Key('symbol-fixed-footer')));
    await tester.drag(find.byKey(const Key('symbol-settings-scroll')),
      const Offset(0, -400));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const Key('symbol-fixed-footer'))),
      before);
    await tester.tap(find.byKey(const Key('symbol-cancel')));
    expect(cancelled, 1);
    expect(committed, isNull);
  });

  testWidgets('precision and timezone dropdowns commit selected values',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 872));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ChartSymbolSettings? committed;
    await mount(tester, onApply: (s) => committed = s,
      onCancel: () {});
    await tester.tap(find.byKey(const Key('symbol-precision')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UTC').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('symbol-apply')));
    expect(committed?.precisionDigits, 4);
    expect(committed?.timeZone, ChartTimeZone.utc);
  });
}
