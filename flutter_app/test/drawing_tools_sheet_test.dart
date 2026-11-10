import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/drawing_tools_sheet.dart';
import 'package:tradelab_flutter/theme/tradelab_theme.dart';

void main() {
  test('Gann and Fibonacci catalog has 15 individually defined tools', () {
    final gann = DrawingCatalogKind.values
        .where((t) => t.category == DrawingCategory.gann).toList();
    expect(gann.length, 15);
    expect(gann.take(3), [
      DrawingCatalogKind.fibonacciRetracement,
      DrawingCatalogKind.fibonacciExtension,
      DrawingCatalogKind.fibonacciChannel,
    ]);
    expect(gann.skip(12), [
      DrawingCatalogKind.fixedGannSquare,
      DrawingCatalogKind.gannSquare,
      DrawingCatalogKind.gannFan,
    ]);
    expect(gann.where((t) => t.implemented),
        [DrawingCatalogKind.fibonacciRetracement]);
  });

  Future<void> pumpCatalog(WidgetTester tester, {
    Size size = const Size(345.5, 768),
    ValueChanged<DrawingCatalogKind>? onSelect,
    ValueChanged<DrawingCatalogKind>? onUnavailable,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: TradeTheme.light(),
      home: Scaffold(body: Builder(builder: (context) => Center(
        child: TextButton(
          key: const Key('open-drawings'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DrawingToolsSheet(
              favorites: {DrawingCatalogKind.fibonacciRetracement},
              onFavoritesChanged: (_) {},
              onSelect: onSelect ?? (_) {},
              onUnavailable: onUnavailable ?? (_) {},
            ),
          ),
          child: const Text('Open drawing tools'),
        ),
      ))),
    ));
    await tester.tap(find.byKey(const Key('open-drawings')));
    await tester.pumpAndSettle();
  }

  testWidgets('reference RTL placement, title, search and favorite star',
      (tester) async {
    await pumpCatalog(tester);
    expect(find.text('رسومات'), findsOneWidget);
    expect(find.byKey(const Key('drawing-tools-search')), findsOneWidget);
    expect(find.byKey(const Key('drawing-category-gann')), findsOneWidget);
    expect(find.byKey(const Key('drawing-favorite-fibonacciRetracement')),
        findsOneWidget);
    final right = tester.getRect(
        find.byKey(const Key('drawing-tool-fibonacciRetracement')));
    final middle = tester.getRect(
        find.byKey(const Key('drawing-tool-fibonacciExtension')));
    final left = tester.getRect(
        find.byKey(const Key('drawing-tool-fibonacciChannel')));
    expect(right.left, greaterThan(middle.right));
    expect(middle.left, greaterThan(left.right));
    expect(right.top, moreOrLessEquals(middle.top, epsilon: .5));
    expect(middle.top, moreOrLessEquals(left.top, epsilon: .5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds actual tools; unsupported choice never selects',
      (tester) async {
    var selected = 0, unavailable = 0;
    await pumpCatalog(tester,
      onSelect: (_) => selected++,
      onUnavailable: (_) => unavailable++,
    );
    await tester.enterText(find.byKey(const Key('drawing-tools-search')),
        'امتداد');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-tool-fibonacciExtension')),
        findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-fibonacciChannel')),
        findsNothing);
    await tester.tap(find.byKey(const Key('drawing-tool-fibonacciExtension')));
    await tester.pump();
    expect(unavailable, 1);
    expect(selected, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press toggles favorite; favorites tab filters list',
      (tester) async {
    await pumpCatalog(tester);
    final extension = find.byKey(const Key('drawing-tool-fibonacciExtension'));
    await tester.longPress(extension);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-favorite-fibonacciExtension')),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('drawing-category-favorites')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawing-category-favorites')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-tool-fibonacciRetracement')),
        findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-fibonacciExtension')),
        findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-gannBox')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference-sized visual fixture of selected Gann catalog',
      (tester) async {
    await pumpCatalog(tester);
    await expectLater(find.byKey(const Key('drawing-tools-bottom-sheet')),
        matchesGoldenFile('goldens/gann_fibonacci_drawing_tools.png'));
  });

  for (final size in const [Size(320,640), Size(360,800), Size(390,844)]) {
    testWidgets('no overflow on phone ${size.width}x${size.height}',
        (tester) async {
      await pumpCatalog(tester,size:size);
      expect(find.byKey(const Key('drawing-tools-grid')),findsOneWidget);
      await tester.drag(find.byKey(const Key('drawing-tools-grid')),
          const Offset(0,-450));
      await tester.pump();
      expect(tester.takeException(),isNull);
    });
  }
}
