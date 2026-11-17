import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/account_screen.dart';
import 'package:tradelab_flutter/screens/markets_screen.dart';
import 'package:tradelab_flutter/screens/results_screen.dart';
import 'package:tradelab_flutter/theme/tradelab_theme.dart';

Widget host(Widget page, {double scale = 1}) => MaterialApp(
  theme: TradeTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Directionality(textDirection: TextDirection.rtl,
      child: Scaffold(body: page)),
);

void main() {
  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('Results has a compact header without empty dash-card grid '
        'on ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(host(ResultsScreen(controller: market)));
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('results-compact-header'));
      expect(header, findsOneWidget);
      expect(tester.getSize(header).height, lessThan(125),
          reason: 'Results tabs must not push the analysis off the screen');
      final body = find.byKey(const Key('results-dashboard-list'));
      await tester.scrollUntilVisible(
        find.text('إحصائيات الصفقات'), 220,
        scrollable: find.descendant(of: body, matching: find.byType(Scrollable)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results-statistics-grid')), findsNothing,
          reason: 'Do not display nine blank metrics with no closed trades');
      expect(find.textContaining('تظهر الإحصائيات بعد إغلاق أول صفقة'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Account connection hero and broker cards are reachable '
        'on ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(host(AccountScreen(
        controller: market, darkMode: false, onDarkModeChanged: (_) {})));
      await tester.pumpAndSettle();
      final hero = find.byKey(const Key('account-connection-hero'));
      expect(hero, findsOneWidget);
      expect(tester.getTopLeft(hero).dy, lessThan(150));
      expect(find.text('cTrader'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Watchlist shows quote rows below a small search/filter '
        'header on ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(host(MarketsScreen(controller: market)));
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('watchlist-compact-header'));
      expect(header, findsOneWidget);
      expect(tester.getSize(header).height, lessThan(220));
      expect(find.byKey(const Key('watchlist-search')), findsOneWidget);
      expect(find.byKey(const Key('market-open-chart-XAUUSD')),
          findsOneWidget);
      expect(find.byKey(const Key('market-open-chart-EURUSD')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
