import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('successful authenticated responses identify their originating token',
      () async {
    final updates = <(String, String)>[];
    final api = MarketApi(
      onSessionRefresh: (oldToken, newToken) => updates.add((oldToken, newToken)),
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer original');
        return http.Response(jsonEncode({'accounts': <Object>[]}), 200,
            headers: {'x-tradelab-session': 'rotated'});
      }),
    );
    expect(await api.accounts('original'), isEmpty);
    expect(updates, [('original', 'rotated')]);
    api.close();
  });

  test('401 and malformed gateway responses never rotate stored credentials',
      () async {
    final updates = <(String, String)>[];
    var requestNumber = 0;
    final api = MarketApi(
      onSessionRefresh: (oldToken, newToken) => updates.add((oldToken, newToken)),
      client: MockClient((request) async {
        requestNumber++;
        return requestNumber == 1
            ? http.Response('{}', 401,
                headers: {'x-tradelab-session': 'untrusted-401'})
            : http.Response('not-json', 200,
                headers: {'x-tradelab-session': 'untrusted-body'});
      }),
    );
    await expectLater(api.accounts('original'),
        throwsA(isA<MarketDataException>()));
    await expectLater(api.accounts('original'),
        throwsA(isA<MarketDataException>()));
    expect(updates, isEmpty);
    api.close();
  });

  test('late broker refresh after disconnect cannot restore the old login',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'tradelab_flutter_ctrader_session': 'original',
    });
    final enteredSpot = Completer<void>();
    final delayedSpot = Completer<http.Response>();
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/accounts':
          return http.Response(jsonEncode({'accounts': [
            {'accountId': '456', 'broker': 'test broker', 'isLive': false},
          ]}), 200);
        case '/v1/symbols':
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42},
          ]}), 200);
        case '/v1/spot':
          enteredSpot.complete();
          return delayedSpot.future;
        default:
          fail('Unexpected gateway endpoint: ${request.url.path}');
      }
    });
    final controller = MarketController(api: MarketApi(client: client));
    addTearDown(controller.dispose);
    await controller.initialize(enableDeepLinks: false);
    expect(controller.ctraderConnected, isTrue);

    final quoteFuture = controller.paperQuote(
        tradeSymbols.firstWhere((symbol) => symbol.code == 'XAUUSD'));
    await enteredSpot.future;
    await controller.disconnect();
    delayedSpot.complete(http.Response(jsonEncode({
      'source': 'ctrader', 'symbolId': '42', 'timestamp': 1700000000000,
      'bid': 2000, 'ask': 2000.2,
    }), 200, headers: {'x-tradelab-session': 'refreshed-too-late'}));
    await expectLater(quoteFuture, throwsA(isA<MarketDataException>()));
    expect(controller.ctraderConnected, isFalse);

    // Recreating the controller checks the actual encrypted-storage state,
    // not just the in-memory null token.
    final reloaded = MarketController(api: MarketApi(client: client));
    addTearDown(reloaded.dispose);
    await reloaded.initialize(enableDeepLinks: false);
    expect(reloaded.ctraderConnected, isFalse);
  });

  test('history from a previous broker account is rejected after switching',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'tradelab_flutter_ctrader_session': 'original',
    });
    final enteredHistory = Completer<void>();
    final delayedHistory = Completer<http.Response>();
    final api = MarketApi(client: MockClient((request) async {
      switch (request.url.path) {
        case '/v1/accounts':
          return http.Response(jsonEncode({'accounts': [
            {'accountId': '456', 'broker': 'broker A'},
            {'accountId': '789', 'broker': 'broker B'},
          ]}), 200);
        case '/v1/symbols':
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42},
          ]}), 200);
        case '/v1/candles':
          expect(request.url.queryParameters['accountId'], '456');
          enteredHistory.complete();
          return delayedHistory.future;
        default:
          fail('Unexpected gateway endpoint: ${request.url.path}');
      }
    }));
    final controller = MarketController(api: api);
    addTearDown(controller.dispose);
    await controller.initialize(enableDeepLinks: false);
    expect(controller.accountId, '456');
    final history = controller.history(
        tradeSymbols.firstWhere((symbol) => symbol.code == 'XAUUSD'),
        '15m', before: DateTime.utc(2026, 11, 8));
    await enteredHistory.future;
    controller.chooseAccount('789');
    delayedHistory.complete(http.Response(jsonEncode({
      'source': 'ctrader', 'period': 'M15', 'symbolId': '42',
      'candles': <Object>[],
    }), 200));
    await expectLater(history, throwsA(isA<MarketDataException>()));
    expect(controller.accountId, '789');
  });
}
