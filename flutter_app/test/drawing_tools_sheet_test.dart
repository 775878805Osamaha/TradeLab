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

  test('trend tools preserve the exact 17-card RTL order and support flags', () {
    final trend = DrawingCatalogKind.values
        .where((tool) => tool.category == DrawingCategory.trend).toList();
    expect(trend, [
      DrawingCatalogKind.trendLine,
      DrawingCatalogKind.ray,
      DrawingCatalogKind.infoLine,
      DrawingCatalogKind.extendedLine,
      DrawingCatalogKind.trendAngle,
      DrawingCatalogKind.horizontal,
      DrawingCatalogKind.horizontalRay,
      DrawingCatalogKind.verticalLine,
      DrawingCatalogKind.crossLine,
      DrawingCatalogKind.parallelChannel,
      DrawingCatalogKind.regressionTrend,
      DrawingCatalogKind.flatTopBottom,
      DrawingCatalogKind.disjointChannel,
      DrawingCatalogKind.pitchfork,
      DrawingCatalogKind.schiffPitchfork,
      DrawingCatalogKind.modifiedSchiffPitchfork,
      DrawingCatalogKind.insidePitchfork,
    ]);
    expect(trend.where((tool) => tool.implemented).toList(), [
      DrawingCatalogKind.trendLine,
      DrawingCatalogKind.ray,
      DrawingCatalogKind.extendedLine,
      DrawingCatalogKind.horizontal,
      DrawingCatalogKind.horizontalRay,
      DrawingCatalogKind.verticalLine,
      DrawingCatalogKind.parallelChannel,
    ]);
  });

  test('favorites codec preserves selection across process restart', () {
    final original = {
      DrawingCatalogKind.trendLine,
      DrawingCatalogKind.horizontalRay,
      DrawingCatalogKind.verticalLine,
    };
    final encoded = DrawingFavoritesCodec.encode(original);
    expect(DrawingFavoritesCodec.decode(encoded), original);
    expect(DrawingFavoritesCodec.decode(
        '["trendLine","unknownFutureTool","ray"]'), {
      DrawingCatalogKind.trendLine, DrawingCatalogKind.ray,
    });
  });

  Future<void> pumpCatalog(WidgetTester tester, {
    Size size = const Size(345.5, 768),
    DrawingCategory initialCategory = DrawingCategory.gann,
    ValueChanged<DrawingCatalogKind>? onSelect,
    ValueChanged<DrawingCatalogKind>? onUnavailable,
    ValueChanged<Set<DrawingCatalogKind>>? onFavoritesChanged,
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
              initialCategory: initialCategory,
              favorites: {
                DrawingCatalogKind.fibonacciRetracement,
                DrawingCatalogKind.trendLine,
                DrawingCatalogKind.horizontal,
                DrawingCatalogKind.horizontalRay,
                DrawingCatalogKind.verticalLine,
              },
              onFavoritesChanged: onFavoritesChanged ?? (_) {},
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

  testWidgets('PROMPT 05: selected trend tab, 3 RTL columns and 2 last tiles',
      (tester) async {
    await pumpCatalog(tester, initialCategory: DrawingCategory.trend);
    final right = tester.getRect(
        find.byKey(const Key('drawing-tool-trendLine')));
    final center = tester.getRect(
        find.byKey(const Key('drawing-tool-ray')));
    final left = tester.getRect(
        find.byKey(const Key('drawing-tool-infoLine')));
    expect(right.left, greaterThan(center.right));
    expect(center.left, greaterThan(left.right));
    expect(right.top, moreOrLessEquals(left.top, epsilon: .5));
    final lastRight = tester.getRect(
        find.byKey(const Key('drawing-tool-modifiedSchiffPitchfork')));
    final lastCenter = tester.getRect(
        find.byKey(const Key('drawing-tool-insidePitchfork')));
    expect(lastRight.left, greaterThan(lastCenter.right));
    expect(lastRight.top, greaterThan(right.top));
    for (final favorite in [
      DrawingCatalogKind.trendLine,
      DrawingCatalogKind.horizontal,
      DrawingCatalogKind.horizontalRay,
      DrawingCatalogKind.verticalLine,
    ]) {
      expect(find.byKey(Key('drawing-favorite-${favorite.name}')),
          findsOneWidget);
    }
    expect(find.byKey(const Key('drawing-favorite-ray')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PROMPT 05: ray selected; unsupported fork shows unavailable',
      (tester) async {
    final selected = <DrawingCatalogKind>[];
    final unsupported = <DrawingCatalogKind>[];
    await pumpCatalog(tester, initialCategory: DrawingCategory.trend,
      onSelect: selected.add, onUnavailable: unsupported.add);
    await tester.tap(find.byKey(const Key('drawing-tool-ray')));
    await tester.pump();
    expect(selected, [DrawingCatalogKind.ray]);
    await tester.drag(find.byKey(const Key('drawing-tools-grid')),
        const Offset(0, -650));
    await tester.pump();
    await tester.tap(find.byKey(const Key('drawing-tool-insidePitchfork')));
    await tester.pump();
    expect(unsupported, [DrawingCatalogKind.insidePitchfork]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PROMPT 05: search, toggle favorite, and notify persistence',
      (tester) async {
    Set<DrawingCatalogKind>? changed;
    await pumpCatalog(tester, initialCategory: DrawingCategory.trend,
      onFavoritesChanged: (value) => changed = value);
    await tester.enterText(find.byKey(const Key('drawing-tools-search')),
        'شعاع');
    await tester.pump();
    expect(find.byKey(const Key('drawing-tool-ray')), findsOneWidget);
    expect(find.byKey(const Key('drawing-tool-horizontalRay')),
        findsOneWidget);
    await tester.longPress(find.byKey(const Key('drawing-tool-ray')));
    await tester.pump();
    expect(changed, contains(DrawingCatalogKind.ray));
    expect(find.byKey(const Key('drawing-favorite-ray')), findsOneWidget);
  });

  testWidgets('PROMPT 05: 17 trend tiles golden reference',
      (tester) async {
    await pumpCatalog(tester, initialCategory: DrawingCategory.trend);
    await expectLater(find.byKey(const Key('drawing-tools-bottom-sheet')),
        matchesGoldenFile('goldens/trend_drawing_tools.png'));
  });

  for (final size in const [Size(320,640), Size(360,800), Size(390,844)]) {
    testWidgets('PROMPT 05 no overflow on trend grid ${size.width}x${size.height}',
        (tester) async {
      await pumpCatalog(tester, size:size,
          initialCategory: DrawingCategory.trend);
      await tester.drag(find.byKey(const Key('drawing-tools-grid')),
          const Offset(0,-450));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

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
