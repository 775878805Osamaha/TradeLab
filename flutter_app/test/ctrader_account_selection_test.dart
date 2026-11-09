import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';

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
}
