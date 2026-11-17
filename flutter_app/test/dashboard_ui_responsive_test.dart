import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/screens/account_screen.dart';
import 'package:tradelab_flutter/screens/markets_screen.dart';
import 'package:tradelab_flutter/screens/results_screen.dart';
import 'package:tradelab_flutter/theme/tradelab_theme.dart';

Widget _app(Widget child, {bool dark = false}) => MaterialApp(
  theme: TradeTheme.light(),
  darkTheme: TradeTheme.dark(),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
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
      await tester.ensureVisible(find.byKey(const Key('dark-mode-switch')));
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
}
