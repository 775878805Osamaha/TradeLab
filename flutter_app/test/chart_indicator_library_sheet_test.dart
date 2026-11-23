import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library.dart';
import 'package:tradelab_flutter/chart/chart_indicator_library_sheet.dart';

void main() {
  Future<void> showLibrary(WidgetTester tester,
      void Function(ChartIndicatorLibraryState) onChanged,
      {Size size = const Size(390, 844),
       ChartIndicatorLibraryState state =
          const ChartIndicatorLibraryState()}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChartIndicatorLibrarySheet(
          initial: state,
          onChange: onChanged,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('search and toggle supported indicators on 320dp RTL phone',
      (tester) async {
    var state = const ChartIndicatorLibraryState();
    await showLibrary(tester, (s) => state = s,
        size: const Size(320, 640));
    expect(find.byKey(const Key('indicator-library-title')), findsOneWidget);
    expect(find.byKey(const Key('indicator-row-sma-12')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('indicator-library-search')), '50');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('indicator-row-sma-50')), findsOneWidget);
    expect(find.byKey(const Key('indicator-row-sma-12')), findsNothing);
    await tester.tap(find.byKey(const Key('indicator-row-sma-50')));
    await tester.pumpAndSettle();
    expect(state.active.single.period, 50);
    expect(find.text('1 مضافة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('indicator-row-sma-50')));
    await tester.pumpAndSettle();
    expect(state.active, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites and active list share current chart indicator state',
      (tester) async {
    var state = const ChartIndicatorLibraryState();
    await showLibrary(tester, (s) => state = s);
    await tester.tap(find.byKey(const Key('indicator-favorite-sma-20')));
    await tester.pumpAndSettle();
    expect(state.favoriteIds, contains('sma-20'));
    await tester.tap(find.byKey(const Key('indicator-tab-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('indicator-row-sma-20')), findsOneWidget);
    expect(find.byKey(const Key('indicator-row-sma-50')), findsNothing);
    await tester.tap(find.byKey(const Key('indicator-row-sma-20')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('indicator-tab-3')));
    await tester.tap(find.byKey(const Key('indicator-tab-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('indicator-row-sma-20')), findsOneWidget);
    expect(state.active.single.period, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pine editor stores complex strategy without fake chart overlay',
      (tester) async {
    var state = const ChartIndicatorLibraryState();
    await showLibrary(tester, (s) => state = s);
    await tester.tap(find.byKey(const Key('indicator-tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('indicator-import-pine')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('indicator-pine-capability')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('indicator-script-title')),
        'Unsupported User Strategy');
    await tester.enterText(
        find.byKey(const Key('indicator-script-source')),
        '//@version=6\nstrategy("Unsupported User Strategy")\n'
        'strategy.entry("Buy", strategy.long)');
    await tester.tap(find.byKey(const Key('indicator-script-save')));
    await tester.pumpAndSettle();
    expect(state.scripts, hasLength(1));
    expect(state.active, isEmpty);
    expect(find.text('Unsupported User Strategy'), findsOneWidget);
    expect(find.textContaining('يتطلب دعم Pine Script'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('simple supported Pine SMA appears in My Scripts and activates',
      (tester) async {
    var state = const ChartIndicatorLibraryState();
    await showLibrary(tester, (s) => state = s);
    await tester.tap(find.byKey(const Key('indicator-tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('indicator-import-pine')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('indicator-script-title')), 'My SMA 21');
    await tester.enterText(
      find.byKey(const Key('indicator-script-source')),
      '//@version=6\nindicator("My SMA", overlay=true)\n'
      'plot(ta.sma(close, 21))',
    );
    await tester.tap(find.byKey(const Key('indicator-script-save')));
    await tester.pumpAndSettle();
    expect(state.scripts.single.supportedSmaPeriod, 21);
    final id = state.scripts.single.id;
    await tester.tap(find.byKey(Key('indicator-row-' + id)));
    await tester.pumpAndSettle();
    expect(state.active.single.period, 21);
    expect(state.active.single.custom, isTrue);
    expect(tester.takeException(), isNull);
  });


  testWidgets('study settings change configured length and stay in library',
      (tester) async {
    var state=const ChartIndicatorLibraryState();
    await showLibrary(tester,(s)=>state=s);
    await tester.tap(find.byKey(const Key('indicator-settings-ema-21')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('indicator-settings-dialog')),
        findsOneWidget);
    await tester.enterText(find.byKey(
      const Key('indicator-length-input')),'34');
    await tester.tap(find.byKey(const Key('indicator-length-save')));
    await tester.pumpAndSettle();
    expect(state.periodOverrides['ema-21'],34);
    expect(find.text('EMA 34'),findsOneWidget);
    await tester.tap(find.byKey(const Key('indicator-row-ema-21')));
    await tester.pumpAndSettle();
    expect(state.active.single.period,34);
    expect(tester.takeException(),isNull);
  });
  testWidgets('saved multi-plot Pine can be edited and re-added from My Scripts',
      (tester) async {
    var state = const ChartIndicatorLibraryState();
    await showLibrary(tester, (value) => state = value);
    await tester.tap(find.byKey(const Key('indicator-tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('indicator-import-pine')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('indicator-script-title')), 'Two Lines');
    await tester.enterText(
      find.byKey(const Key('indicator-script-source')),
      'indicator("Two", overlay=true)\na = ta.sma(close,2)\n'
      'plot(a)\nplot(a+2)');
    await tester.tap(find.byKey(const Key('indicator-script-save')));
    await tester.pumpAndSettle();
    final id = state.scripts.single.id;
    expect(state.supported.singleWhere((v) => v.id == id).kind,
      ChartIndicatorKind.pine);
    await tester.tap(find.byKey(Key('indicator-row-' + id)));
    await tester.pumpAndSettle();
    expect(state.active, hasLength(1));
    await tester.tap(find.byKey(Key('indicator-edit-' + id)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('indicator-pine-editor')), findsOneWidget);
    await tester.enterText(find.byKey(
      const Key('indicator-script-source')),
      'indicator("Unsupported", overlay=true)\nplotshape(close)');
    await tester.tap(find.byKey(const Key('indicator-script-save')));
    await tester.pumpAndSettle();
    expect(state.scripts, hasLength(1));
    expect(state.active, isEmpty);
    expect(find.byKey(Key('indicator-unsupported-' + id)),
      findsOneWidget);
    expect(find.textContaining('السطر'), findsWidgets);
    await tester.tap(find.byKey(Key('indicator-delete-' + id)));
    await tester.pumpAndSettle();
    expect(state.scripts, isEmpty);
    expect(tester.takeException(), isNull);
  });


}
