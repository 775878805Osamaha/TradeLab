import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/ctrader_session_token_write_queue.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quick cTrader A-B-A taps persist the last selected account', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final values = <String?>[];
    var concurrent = 0;
    var maximum = 0;
    final writer = CTraderSerializedSecureValueWriteQueue((account) async {
      concurrent++;
      if (concurrent > maximum) maximum = concurrent;
      if (account == '101') {
        // Only stall the first tap, not the later A in A->B->A.
        if (!firstStarted.isCompleted) {
          firstStarted.complete();
          await releaseFirst.future;
        }
      }
      values.add(account);
      concurrent--;
    });
    final first = writer.persist('101');
    await firstStarted.future;
    final second = writer.persist('202');
    final third = writer.persist('101');
    expect(values, isEmpty);
    expect(concurrent, 1);
    releaseFirst.complete();
    await Future.wait([first, second, third]);
    expect(values, ['101', '202', '101']);
    expect(maximum, 1, reason: 'Secure storage writes cannot race');
  });

  test('logout wipes saved broker after an already started write', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    String? stored;
    final writer = CTraderSerializedSecureValueWriteQueue((account) async {
      if (account == '202') {
        started.complete();
        await release.future;
      }
      stored = account;
    });
    final selecting = writer.persist('202');
    await started.future;
    final disconnecting = writer.persist(null);
    release.complete();
    await Future.wait([selecting, disconnecting]);
    expect(stored, isNull);
  });

  test('fast user selections survive restart, then are cleared at logout',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'tradelab_flutter_ctrader_session', value: 'session-fixture');
    MockClient client({bool reversed = false}) => MockClient((request) async {
      expect(request.url.path, '/v1/accounts');
      final accounts = [
        {'accountId': '101', 'broker': 'Demo Account', 'isLive': false},
        {'accountId': '202', 'broker': 'Live Account', 'isLive': true},
      ];
      return http.Response(jsonEncode({
        'accounts': reversed ? accounts.reversed.toList() : accounts,
      }), 200);
    });
    final api = MarketApi(client: client());
    final controller = MarketController(api: api, storage: storage);
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await controller.initialize(enableDeepLinks: false);
    expect(controller.accountId, '101');
    controller.chooseAccount('202');
    controller.chooseAccount('101');
    controller.chooseAccount('202');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_selected_account'), '202');

    final reopenedApi = MarketApi(client: client(reversed: true));
    final reopened = MarketController(api: reopenedApi, storage: storage);
    addTearDown(reopened.dispose);
    addTearDown(reopenedApi.close);
    await reopened.initialize(enableDeepLinks: false);
    expect(reopened.accountId, '202');
    expect(reopened.accounts.first.id, '202');
    await reopened.disconnect();
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_session'), isNull);
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_selected_account'), isNull);
  });

  test('OAuth re-link retains authorized live account and clears lost access',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'tradelab_flutter_ctrader_session', value: 'initial-session');
    var grants = 0;
    var permitsLive = true;
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/auth/ctrader/redeem') {
        grants++;
        return http.Response(jsonEncode({
          'permission': 'read_only',
          'sessionToken': 'new-session-$grants',
        }), 200);
      }
      expect(request.url.path, '/v1/accounts');
      return http.Response(jsonEncode({
        'accounts': [
          {'accountId': '101', 'broker': 'Demo Account', 'isLive': false},
          if (permitsLive)
            {'accountId': '202', 'broker': 'Live Account', 'isLive': true},
        ],
      }), 200);
    }));
    final controller = MarketController(api: api, storage: storage);
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await controller.initialize(enableDeepLinks: false);
    controller.chooseAccount('202');

    Future<void> reauthorize(int attempt) async {
      await storage.write(key: 'tradelab_flutter_oauth_pending',
        value: jsonEncode({
          'verifier': 'test-pkce-verifier-$attempt',
          'created': DateTime.now().toUtc().millisecondsSinceEpoch,
        }));
      await controller.completeOAuth(Uri.parse(
        'tradelabflutter://oauth/ctrader?ticket=fixture-$attempt'));
    }

    await reauthorize(1);
    expect(controller.accountId, '202',
      reason: 'New grant still authorizes the user-selected live account');
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_selected_account'), '202');
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_session'), 'new-session-1');

    permitsLive = false;
    await reauthorize(2);
    expect(controller.accountId, '101',
      reason: 'Old live account is no longer authorized by the new OAuth grant');
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_selected_account'), '101',
      reason: 'Restart must not reselect a now-forbidden broker');
    expect(await storage.read(
        key: 'tradelab_flutter_ctrader_session'), 'new-session-2');
  });
}
