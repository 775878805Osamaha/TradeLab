import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_type_sheet.dart';
import 'package:tradelab_flutter/theme/tradelab_theme.dart';

void main() {
  test('reference catalog lists exactly 21 kinds in seven RTL rows', () {
    expect(ChartKind.values.length, 21);
    expect(ChartKind.values.take(3), [
      ChartKind.bars, ChartKind.candles, ChartKind.hollowCandles,
    ]);
    expect(ChartKind.values.skip(18), [
      ChartKind.kagi, ChartKind.pointAndFigure, ChartKind.range,
    ]);
    expect(ChartKind.values.where((k) => k.implemented).toList(), [
      ChartKind.candles, ChartKind.heikinAshi, ChartKind.range,
    ]);
  });

  Future<void> pumpPicker(WidgetTester tester,
      {Size logicalSize = const Size(360, 800),
      ChartKind selected = ChartKind.candles}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = logicalSize * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: TradeTheme.light(),
      home: Scaffold(body: Builder(builder: (context) => Center(
        child: TextButton(
          key: const Key('open-picker'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ChartTypeSheet(
              selected: selected,
              onSelect: (_) {},
              onUnavailable: (_) {},
            ),
          ),
          child: const Text('Open picker'),
        ),
      ))),
    ));
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('selected candle card sits between bars and hollow candles',
      (tester) async {
    await pumpPicker(tester);
    final right = tester.getRect(find.byKey(const Key('chart-kind-bars')));
    final center = tester.getRect(find.byKey(const Key('chart-kind-candles')));
    final left = tester.getRect(find.byKey(const Key('chart-kind-hollowCandles')));
    expect(right.top, moreOrLessEquals(center.top, epsilon: .5));
    expect(left.top, moreOrLessEquals(center.top, epsilon: .5));
    expect(right.left, greaterThan(center.right));
    expect(center.left, greaterThan(left.right));
    expect(tester.widget<ChartKindCard>(find.byType(ChartKindCard).at(1)).selected,
        isTrue);
    expect(find.text('نوع الرسم البياني'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference-sized Flutter screenshot of open, selected sheet',
      (tester) async {
    await pumpPicker(tester, logicalSize: const Size(345.5, 768));
    await expectLater(find.byKey(const Key('chart-type-bottom-sheet')),
        matchesGoldenFile('goldens/chart_type_sheet_selected_candles.png'));
  });

  for (final width in const [320.0, 360.0, 390.0]) {
    testWidgets('no overflow at phone width ' + width.toString(),
        (tester) async {
      await pumpPicker(tester,
          logicalSize: Size(width, width == 320 ? 640 : 800));
      expect(find.byKey(const Key('chart-type-bottom-sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final grid = find.byKey(const Key('chart-type-grid'));
      await tester.drag(grid, const Offset(0, -850));
      await tester.pump();
      expect(find.byKey(const Key('chart-kind-range')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unsupported Renko never becomes an invented active chart',
      (tester) async {
    var chosen = 0;
    var unsupported = 0;
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(720, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ChartTypeSheet(
        selected: ChartKind.candles,
        onSelect: (_) => chosen++,
        onUnavailable: (_) => unsupported++,
      ),
    )));
    final renko = find.byKey(const Key('chart-kind-renko'));
    await tester.scrollUntilVisible(renko, 160,
        scrollable: find.byKey(const Key('chart-type-grid')));
    await tester.pump();
    await tester.tap(renko);
    await tester.pump();
    expect(unsupported, 1);
    expect(chosen, 0);
    await tester.drag(find.byKey(const Key('chart-type-grid')),
        const Offset(0, 850));
    await tester.pump();
    final candleCard = find.ancestor(
      of: find.byKey(const Key('chart-kind-candles')),
      matching: find.byType(ChartKindCard),
    );
    expect(tester.widget<ChartKindCard>(candleCard).selected, isTrue);
  });
}
