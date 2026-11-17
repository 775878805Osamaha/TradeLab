import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/screens/account_screen.dart';
import 'package:tradelab_flutter/screens/markets_screen.dart';
import 'package:tradelab_flutter/screens/results_screen.dart';
import 'package:tradelab_flutter/theme/tradelab_theme.dart';

Widget _app(Widget child, {bool dark = false, double textScale = 1}) => MaterialApp(
  theme: TradeTheme.light(),
  darkTheme: TradeTheme.dark(),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  for (final width in <double>[320, 390, 600]) {
    testWidgets('Results dashboard is RTL and never invents profit at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MarketController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(ResultsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results-net-profit-hero')), findsOneWidget);
      expect(find.text('صافي الربح المحقق'), findsOneWidget);
      expect(find.byKey(const Key('results-period-picker')), findsOneWidget);
      expect(find.textContaining('+20.00 USD'), findsNothing);
      await tester.tap(find.byKey(const Key('results-period-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أسبوع').last);
      await tester.pumpAndSettle();
      expect(find.text('أسبوع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Account dashboard retains connection and appearance actions '
        'at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MarketController();
      addTearDown(controller.dispose);
      var darkRequested = false;
      await tester.pumpWidget(_app(AccountScreen(
        controller: controller,
        darkMode: false,
        onDarkModeChanged: (value) => darkRequested = value,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-connection-hero')), findsOneWidget);
      expect(find.byKey(const Key('ctrader-connect')), findsOneWidget);
      expect(find.text('cTrader'), findsWidgets);
      // Account settings are below the fold on compact phones. Unlike
      // ensureVisible, scrollUntilVisible can materialize a lazy ListView row.
      await tester.scrollUntilVisible(
        find.byKey(const Key('dark-mode-switch')), 180,
        scrollable: find.descendant(
          of: find.byKey(const Key('account-dashboard-list')),
          matching: find.byType(Scrollable)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dark-mode-switch')));
      await tester.pump();
      expect(darkRequested, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Watchlist search, favorites and chart navigation work at '
        '${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MarketController();
      addTearDown(controller.dispose);
      TradeSymbol? selected;
      await tester.pumpWidget(_app(MarketsScreen(
        controller: controller,
        onSymbolSelected: (symbol) => selected = symbol,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('watchlist-search')), findsOneWidget);
      expect(find.byKey(const Key('watchlist-favorites-toggle')),
          findsOneWidget);
      expect(find.byKey(const Key('market-open-chart-XAUUSD')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('market-open-chart-XAUUSD')));
      await tester.pumpAndSettle();
      expect(selected?.code, 'XAUUSD');
      await tester.enterText(find.byKey(const Key('watchlist-search')),
          'NO_SUCH_SYMBOL');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد رموز مطابقة'), findsOneWidget);
      await tester.tap(find.byTooltip('مسح البحث'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('market-open-chart-XAUUSD')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  // A clear, usable Arabic UI must survive the phone's text-size setting and
  // both color themes. These tests render the real screens, not mock cards.
  for (final width in <double>[320, 390]) {
    testWidgets('Dark Results supports enlarged Arabic without layout errors '
        'at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(_app(
        ResultsScreen(controller: market), dark: true, textScale: 1.3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-net-profit-hero')), findsOneWidget);
      expect(find.text('صافي الربح المحقق'), findsOneWidget);
      final renderError = tester.takeException();
      if (renderError != null) {
        final captured = <String>[];
        final oldPrinter = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) captured.add(message);
        };
        try {
          debugDumpRenderTree();
        } finally {
          debugPrint = oldPrinter;
        }
        final lines = captured.join('\n').split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('OVERFLOWING')) {
            // Temporary diagnosis, remove after locating the exact culprit.
            // ignore: avoid_print
            print('RESULTS_320_OVERFLOW: ${lines.skip(i > 12 ? i - 12 : 0).take(38).join('\\n')}');
          }
        }
      }
      expect(renderError, isNull);
    });

    testWidgets('Dark Account supports enlarged Arabic and usable settings '
        'at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(_app(AccountScreen(
        controller: market, darkMode: true, onDarkModeChanged: (_) {}),
        dark: true, textScale: 1.3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-connection-hero')), findsOneWidget);
      expect(find.byKey(const Key('ctrader-connect')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dark Watchlist supports enlarged Arabic and source status '
        'at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(_app(
        MarketsScreen(controller: market), dark: true, textScale: 1.3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('watchlist-search')), findsOneWidget);
      expect(find.byKey(const Key('market-open-chart-XAUUSD')), findsOneWidget);
      expect(find.textContaining('يتطلب ربط cTrader'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

}
