import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/main.dart';

void main() {
  Future<void> openAtPhoneSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const TradeLabApp());
    await tester.pumpAndSettle();
  }

  testWidgets('opens approved RTL chart in analysis mode', (tester) async {
    await openAtPhoneSize(tester);
    expect(find.text('XAUUSD'), findsWidgets);
    expect(find.textContaining('معاينة تصميم Flutter'), findsOneWidget);
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('Replay controls stay inside the chart', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('تشغيل Replay داخل الشارت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsOneWidget);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
    await tester.tap(find.byTooltip('إغلاق Replay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replay-play-pause')), findsNothing);
  });

  testWidgets('chart accepts one-finger drag and returns to latest', (tester) async {
    await openAtPhoneSize(tester);
    final chart = find.byKey(const Key('chart-gesture-area'));
    await tester.drag(chart, const Offset(-130, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('العودة إلى أحدث شمعة'));
    await tester.tap(find.byTooltip('العودة إلى أحدث شمعة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact chart remains readable on narrow screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const TradeLabApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);
  });

  testWidgets('Range candles selector has explicit settings', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.byTooltip('نوع الشموع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شموع المدى').last);
    await tester.pumpAndSettle();
    expect(find.text('إعدادات شموع المدى'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    await tester.tap(find.text('250'));
    await tester.pumpAndSettle();
    expect(find.text('مدى 250'), findsWidgets);
  });

  testWidgets('navigation retains results and account screens', (tester) async {
    await openAtPhoneSize(tester);
    await tester.tap(find.text('النتائج').last);
    await tester.pumpAndSettle();
    expect(find.text('النتائج والتحليلات'), findsOneWidget);
    expect(find.text('صافي الربح'), findsOneWidget);
    await tester.tap(find.text('الحساب').last);
    await tester.pumpAndSettle();
    expect(find.text('الحساب والإعدادات'), findsOneWidget);
    expect(find.byKey(const Key('dark-mode-switch')), findsOneWidget);
  });
}
