import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/screens/account_screen.dart';
import 'package:tradelab_flutter/theme/tradelab_theme.dart';

Widget accountHost(MarketController controller) => MaterialApp(
  theme: TradeTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(1.3)),
    child: child!,
  ),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: AccountScreen(
      controller: controller,
      darkMode: false,
      onDarkModeChanged: (_) {},
    )),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in <double>[320, 390]) {
    testWidgets('account selector follows external A -> B -> A broker switches '
        'at ${width}dp without a stale FormField', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FlutterSecureStorage.setMockInitialValues({
        'tradelab_flutter_ctrader_session': 'widget-test-token',
      });
      const storage = FlutterSecureStorage();
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/accounts');
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'Demo Broker',
            'isLive': false},
          {'accountId': '202',
            'broker': 'Long Real Brokerage Company International',
            'isLive': true},
        ]}), 200);
      });
      final market = MarketController(
        storage: storage, api: MarketApi(client: client));
      addTearDown(market.dispose);
      await market.initialize(enableDeepLinks: false);
      expect(market.ctraderConnected, isTrue);
      expect(market.accountId, '101');

      await tester.pumpWidget(accountHost(market));
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('ctrader-account-selector'));
      expect(selector, findsOneWidget);
      expect(tester.state<FormFieldState<String>>(selector).value, '101');
      expect(find.text('حساب تجريبي · قراءة فقط'), findsOneWidget);

      market.chooseAccount('202');
      await tester.pumpAndSettle();
      expect(tester.state<FormFieldState<String>>(selector).value, '202');
      expect(find.text('حساب حقيقي · قراءة فقط'), findsOneWidget);

      // Return to the original broker through the active dropdown, not by
      // reconstructing the whole account screen from test code.
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Demo Broker').last);
      await tester.pumpAndSettle();
      expect(market.accountId, '101');
      expect(tester.state<FormFieldState<String>>(selector).value, '101');
      // ListView lazily unmounts the hero after the account selector is
      // scrolled into view. Scroll back to verify the actual visible badge.
      await tester.drag(find.byKey(const Key('account-dashboard-list')),
          const Offset(0, 650));
      await tester.pumpAndSettle();
      expect(find.text('حساب تجريبي · قراءة فقط'), findsOneWidget);
      expect(find.text('حساب حقيقي · قراءة فقط'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disconnected read-only cTrader action is visible at top '
        'and disables during account work at ${width}dp', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final market = MarketController();
      addTearDown(market.dispose);
      await tester.pumpWidget(accountHost(market));
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('ctrader-connect'));
      final hero = find.byKey(const Key('account-connection-hero'));
      expect(button, findsOneWidget);
      expect(find.ancestor(of: button, matching: hero), findsOneWidget);
      expect(tester.getRect(button).bottom, lessThan(460));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(46));
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      market.busy = true;
      market.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
