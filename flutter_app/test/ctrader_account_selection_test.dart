import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected cTrader live broker survives app restart and account reorder',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'tradelab_flutter_ctrader_session',
      value: 'session-test-only',
    );
    var reordered = false;
    MarketController buildController() {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/accounts');
        final accounts = [
          {'accountId': '101', 'broker': 'Demo Broker', 'isLive': false},
          {'accountId': '202', 'broker': 'Gold Live Broker', 'isLive': true},
        ];
        return http.Response(jsonEncode({
          'accounts': reordered ? accounts.reversed.toList() : accounts,
        }), 200);
      });
      return MarketController(
        storage: storage, api: MarketApi(client: client),
      );
    }

    final first = buildController();
    await first.initialize(enableDeepLinks: false);
    expect(first.accountId, '101');
    first.chooseAccount('202');
    expect(first.accountId, '202');
    // Asynchronous secure storage write must complete before restart.
    await Future<void>.delayed(const Duration(milliseconds: 15));
    first.dispose();

    reordered = true;
    final reopened = buildController();
    await reopened.initialize(enableDeepLinks: false);
    expect(reopened.accountId, '202');
    expect(reopened.accounts.first.id, '202');
    expect(reopened.accounts.first.isLive, isTrue);
    await reopened.disconnect();
    expect(await storage.read(
      key: 'tradelab_flutter_ctrader_selected_account',
    ), isNull);
    reopened.dispose();
  });

  test('stale cTrader quote response cannot replace a new account price',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'tradelab_flutter_ctrader_session', value: 'test-session');

    final oldSpotReached = Completer<void>();
    final releaseOldSpot = Completer<http.Response>();
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/accounts') {
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'Broker A', 'isLive': false},
          {'accountId': '202', 'broker': 'Broker B', 'isLive': false},
        ]}), 200);
      }
      if (path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      if (path == '/v1/spot') {
        final account = request.url.queryParameters['accountId'];
        if (account == '101') {
          if (!oldSpotReached.isCompleted) oldSpotReached.complete();
          return releaseOldSpot.future;
        }
        expect(account, '202');
        return http.Response(jsonEncode({
          'source': 'ctrader', 'accountId': '202', 'symbolId': '42',
          'bid': 3882, 'ask': 3882.2,
          'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
        }), 200);
      }
      fail('Unexpected API request: ${request.url}');
    });

    final controller = MarketController(
        storage: storage, api: MarketApi(client: client));
    addTearDown(controller.dispose);
    await controller.initialize(enableDeepLinks: false);
    expect(controller.accountId, '101');
    final gold = tradeSymbols.firstWhere((x) => x.code == 'XAUUSD');

    final oldPriceRequest = controller.paperQuote(gold);
    await oldSpotReached.future.timeout(const Duration(seconds: 3));
    controller.chooseAccount('202');
    final newQuote = await controller.paperQuote(gold);
    expect(newQuote.bid, 3882);
    expect(controller.recentQuoteFor(gold)!.bid, 3882);

    // Register the error expectation before releasing the deferred response:
    // no unhandled asynchronous broker failures are allowed in the test.
    final oldQuoteRejected = expectLater(oldPriceRequest,
        throwsA(isA<MarketDataException>()));
    releaseOldSpot.complete(http.Response(jsonEncode({
      'source': 'ctrader', 'accountId': '101', 'symbolId': '42',
      'bid': 3701, 'ask': 3701.2,
      'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
    }), 200));
    await oldQuoteRejected;
    expect(controller.accountId, '202');
    expect(controller.recentQuoteFor(gold)!.bid, 3882,
        reason: 'An old account cannot overwrite a freshly verified quote');
  });

  testWidgets('hidden cTrader chart refetches the chosen account on return',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'tradelab_flutter_ctrader_session', value: 'test-session');

    final requestedAccounts = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      final account = request.url.queryParameters['accountId'] ?? '';
      if (path == '/v1/accounts') {
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'Broker A', 'isLive': false},
          {'accountId': '202', 'broker': 'Broker B', 'isLive': false},
        ]}), 200);
      }
      if (path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      if (path == '/v1/spot') {
        return http.Response(jsonEncode({
          'source': 'ctrader', 'accountId': account,
          'symbolId': '42', 'bid': account == '101' ? 3880 : 3900,
          'ask': account == '101' ? 3880.2 : 3900.2,
          'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
        }), 200);
      }
      if (path == '/v1/candles') {
        requestedAccounts.add(account);
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        final closedOpen = (now ~/ 60000) * 60000 - 60000;
        final price = account == '101' ? 3880 : 3900;
        return http.Response(jsonEncode({
          'source': 'ctrader', 'accountId': account, 'symbolId': '42',
          'period': request.url.queryParameters['period'],
          'hasMore': false,
          'candles': [{
            'timestamp': closedOpen, 'open': price,
            'high': price + 2, 'low': price - 2, 'close': price + 1,
          }],
        }), 200);
      }
      fail('Unexpected API request: ${request.url}');
    });
    final controller = MarketController(
        storage: storage, api: MarketApi(client: client));
    addTearDown(controller.dispose);
    await controller.initialize(enableDeepLinks: false);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(TradeLabApp(controller: controller));
    await tester.pumpAndSettle();
    expect(requestedAccounts, contains('101'));
    expect(find.byKey(const Key('chart-gesture-area')), findsOneWidget);

    await tester.tap(find.text('الحساب').last);
    await tester.pumpAndSettle();
    controller.chooseAccount('202');
    await tester.pumpAndSettle();
    expect(requestedAccounts, isNot(contains('202')),
        reason: 'A hidden chart must not fetch or render another account');

    await tester.tap(find.text('رسوم بيانية').last);
    await tester.pumpAndSettle();
    expect(requestedAccounts, contains('202'),
        reason: 'Returning to a chart must reload broker-scoped candles');
    expect(find.byKey(const Key('chart-source-empty')), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
