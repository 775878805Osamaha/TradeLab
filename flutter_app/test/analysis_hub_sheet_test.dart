import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/analysis_hub_sheet.dart';

void main() {
  Future<void> pumpHub(WidgetTester tester,
      ValueChanged<AnalysisHubAction> onAction, {Size size = const Size(390, 844)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter,
        child: AnalysisHubSheet(onAction: onAction)),
    )));
    await tester.pump();
  }

  testWidgets('analysis command order, RTL geometry, and disabled Save',
      (tester) async {
    final commands = <AnalysisHubAction>[];
    await pumpHub(tester, commands.add);
    expect(find.byKey(const Key('analysis-hub-title')), findsOneWidget);
    expect(find.byKey(const Key('analysis-hub-handle')), findsOneWidget);

    const firstRow = [AnalysisHubAction.layoutFormat,
      AnalysisHubAction.layoutManager, AnalysisHubAction.drawingSettings];
    final rects = firstRow.map((action) => tester.getRect(
      find.byKey(Key('analysis-action-${action.name}')))).toList();
    expect(rects[0].top, moreOrLessEquals(rects[1].top, epsilon: .5));
    expect(rects[1].top, moreOrLessEquals(rects[2].top, epsilon: .5));
    expect(rects[0].center.dx, greaterThan(rects[1].center.dx));
    expect(rects[1].center.dx, greaterThan(rects[2].center.dx));

    const secondRow = [AnalysisHubAction.newLayout,
      AnalysisHubAction.saveLayout, AnalysisHubAction.openLayout];
    final second = secondRow.map((action) => tester.getRect(
      find.byKey(Key('analysis-action-${action.name}')))).toList();
    expect(second[0].top, greaterThan(rects[0].bottom));
    expect(second[0].center.dx, greaterThan(second[1].center.dx));
    expect(second[1].center.dx, greaterThan(second[2].center.dx));

    await tester.tap(find.byKey(const Key('analysis-action-saveLayout')));
    await tester.pump();
    expect(commands, isEmpty);
    await tester.tap(find.byKey(const Key('analysis-action-layoutFormat')));
    await tester.pump();
    expect(commands, [AnalysisHubAction.layoutFormat]);
  });

  testWidgets('broker, four large tools and three small tools stay ordered',
      (tester) async {
    final commands = <AnalysisHubAction>[];
    await pumpHub(tester, commands.add);
    final broker = tester.getRect(
      find.byKey(const Key('analysis-action-tradeWithBroker')));
    expect(broker.width, moreOrLessEquals(390 * 631 / 691, epsilon: 1));
    final toolsTitle = tester.getRect(find.text('أدوات'));
    expect(toolsTitle.right, lessThan(390 - 390 * 20 / 691));
    final first = tester.getRect(
      find.byKey(const Key('analysis-action-indicators')));
    final compare = tester.getRect(
      find.byKey(const Key('analysis-action-compare')));
    final second = tester.getRect(
      find.byKey(const Key('analysis-action-alerts')));
    final replay = tester.getRect(
      find.byKey(const Key('analysis-action-replay')));
    final templates = tester.getRect(
      find.byKey(const Key('analysis-action-indicatorTemplates')));
    final chartType = tester.getRect(
      find.byKey(const Key('analysis-action-chartType')));
    final tree = tester.getRect(
      find.byKey(const Key('analysis-action-objectTree')));
    expect(broker.bottom, lessThan(first.top));
    expect(first.center.dx, greaterThan(compare.center.dx));
    expect(second.center.dx, greaterThan(replay.center.dx));
    expect(second.top, greaterThan(first.bottom));
    expect(templates.top, greaterThan(second.bottom));
    expect(templates.center.dx, greaterThan(chartType.center.dx));
    expect(chartType.center.dx, greaterThan(tree.center.dx));

    await tester.ensureVisible(
      find.byKey(const Key('analysis-action-tradeWithBroker')));
    await tester.tap(find.byKey(const Key('analysis-action-tradeWithBroker')));
    await tester.pump();
    expect(commands, [AnalysisHubAction.tradeWithBroker]);
  });

  testWidgets('analysis hub scrolls without overflow on narrow phone',
      (tester) async {
    await pumpHub(tester, (_) {}, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byKey(const Key('analysis-hub-scroll')),
        const Offset(0, -400));
    await tester.pump();
    expect(find.byKey(const Key('analysis-action-symbolInformation')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analysis hub reference golden on 691 logical pixel canvas',
      (tester) async {
    await pumpHub(tester, (_) {}, size: const Size(691, 1536));
    await expectLater(find.byKey(const Key('analysis-hub-sheet')),
      matchesGoldenFile('goldens/analysis_hub_sheet.png'));
  });
}
