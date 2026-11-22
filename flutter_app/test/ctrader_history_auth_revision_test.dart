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

/// Only authenticated response-shaped fixtures. Tests never request live
/// broker history or substitute fabricated market bars in a release build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final gold = tradeSymbols.firstWhere((symbol) => symbol.code == 'XAUUSD');

  http.Response responseFor(http.Request request, {String? refreshedToken}) {
    final path = request.url.path;
    final sourceAccount = request.url.queryParameters['accountId'] ?? '101';
    final headers = refreshedToken == null
        ? <String, String>{}
        : <String, String>{'x-tradelab-session': refreshedToken};
    if (path == '/v1/candles') {
      return http.Response(jsonEncode({
        'source': 'ctrader', 'accountId': sourceAccount,
        'symbolId': '42', 'period': request.url.queryParameters['period'],
        'hasMore': false, 'candles': <Object>[],
      }), 200, headers: headers);
    }
    if (path == '/v1/ticks') {
      final fromMs = int.parse(request.url.queryParameters['from']!);
      return http.Response(jsonEncode({
        'source': 'ctrader', 'accountId': sourceAccount,
        'symbolId': '42', 'quoteType': 'bid',
        'hasMore': false, 'ticks': [
          {'timestamp': fromMs + 1, 'price': 3900.25},
        ],
      }), 200, headers: headers);
    }
    if (path == '/v1/symbol-detail') {
      return http.Response(jsonEncode({
        'source': 'ctrader', 'symbolId': '42', 'digits': 2,
      }), 200, headers: headers);
    }
    throw StateError('Unexpected cTrader fixture route: $path');
  }

  test('A to B to A invalidates every in-flight historical cTrader read',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'tradelab_flutter_ctrader_session', value: 'session-1');

    final started = Completer<void>();
    final pending = <(http.Request, Completer<http.Response>)>[];
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/accounts') {
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'A', 'isLive': false},
          {'accountId': '202', 'broker': 'B', 'isLive': false},
        ]}), 200);
      }
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      final deferred = Completer<http.Response>();
      pending.add((request, deferred));
      if (pending.length == 5 && !started.isCompleted) started.complete();
      return deferred.future;
    }));
    final controller = MarketController(storage: storage, api: api);
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await controller.initialize(enableDeepLinks: false);
    expect(controller.accountId, '101');
    final before = controller.ctraderAuthorizationRevision;
    final reads = <Future<Object?>>[
      controller.history(gold, '1m', before: DateTime.utc(2026, 11, 20)),
      controller.closedCandlesSince(gold, '1m',
          DateTime.now().toUtc().millisecondsSinceEpoch -
              const Duration(minutes: 5).inMilliseconds),
      controller.rangeTicks(
          gold, before: DateTime.utc(2026, 11, 20)),
      controller.rangeTicksBetween(gold,
          fromMs: 1700000000000, toMs: 1700000001000),
      controller.pointSize(gold),
    ];
    await started.future.timeout(const Duration(seconds: 5));
    expect(pending, hasLength(5));
    controller.chooseAccount('202');
    controller.chooseAccount('101');
    expect(controller.accountId, '101');
    expect(controller.ctraderAuthorizationRevision,
        greaterThan(before));

    final rejections = <Future<void>>[
      for (final read in reads)
        expectLater(read, throwsA(isA<MarketDataException>().having(
          (e) => e.message, 'old-source response', contains('تفويض')))),
    ];
    for (final (request, deferred) in pending) {
      deferred.complete(responseFor(request));
    }
    await Future.wait(rejections);
  });

  test('late old-auth header cannot replace new OAuth token for same account',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'tradelab_flutter_ctrader_session', value: 'session-old');
    final oldRequestStarted = Completer<void>();
    final oldResponse = Completer<http.Response>();
    var historyRequests = 0;
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/accounts') {
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'Same Broker', 'isLive': false},
        ]}), 200);
      }
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      if (request.url.path == '/auth/ctrader/redeem') {
        expect(request.method, 'POST');
        return http.Response(jsonEncode({
          'permission': 'read_only', 'sessionToken': 'session-new',
        }), 200);
      }
      if (request.url.path == '/v1/candles') {
        historyRequests++;
        if (historyRequests == 1) {
          expect(request.headers['Authorization'], 'Bearer session-old');
          if (!oldRequestStarted.isCompleted) oldRequestStarted.complete();
          return oldResponse.future;
        }
        expect(request.headers['Authorization'], 'Bearer session-new');
        return responseFor(request, refreshedToken: 'session-rotated');
      }
      throw StateError('Unexpected cTrader fixture route: ${request.url.path}');
    }));
    final controller = MarketController(storage: storage, api: api);
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await controller.initialize(enableDeepLinks: false);
    final revisionBefore = controller.ctraderAuthorizationRevision;
    final oldRead = controller.history(
        gold, '1m', before: DateTime.utc(2026, 11, 20));
    await oldRequestStarted.future.timeout(const Duration(seconds: 5));

    await storage.write(key: 'tradelab_flutter_oauth_pending', value:
      jsonEncode({'verifier': 'test-verifier',
        'created': DateTime.now().toUtc().millisecondsSinceEpoch}));
    await controller.completeOAuth(Uri.parse(
        'tradelabflutter://oauth/ctrader?ticket=fixture-ticket'));
    expect(controller.accountId, '101',
        reason: 'Only the OAuth grant changes, not the account number');
    expect(controller.ctraderAuthorizationRevision,
        greaterThan(revisionBefore));
    expect(await storage.read(key: 'tradelab_flutter_ctrader_session'),
        'session-new');

    final staleRejected = expectLater(oldRead,
      throwsA(isA<MarketDataException>().having(
        (e) => e.message, 'old source', contains('تفويض'))));
    oldResponse.complete(responseFor(
      http.Request('GET', Uri.parse(
        'https://tradelab-vercel-gateway.vercel.app/v1/candles'
        '?accountId=101&symbolId=42&period=M1')),
      refreshedToken: 'session-illicit-old-response'));
    await staleRejected;
    // A response stamped by an older authorized session cannot overwrite
    // new credentials, even though both sessions selected accountId 101.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await storage.read(key: 'tradelab_flutter_ctrader_session'),
        'session-new');

    // Legitimate refresh of the CURRENT session is still allowed and does
    // not change the authorization revision or discard valid chart candles.
    final freshRevision = controller.ctraderAuthorizationRevision;
    final newHistory = await controller.history(
        gold, '1m', before: DateTime.utc(2026, 11, 20));
    expect(newHistory, isEmpty);
    expect(controller.ctraderAuthorizationRevision, freshRevision);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await storage.read(key: 'tradelab_flutter_ctrader_session'),
        'session-rotated');
  });

  test('history completing DURING OAuth re-link cannot publish old source',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'tradelab_flutter_ctrader_session', value: 'session-old');
    final oldStarted = Completer<void>();
    final oldResponse = Completer<http.Response>();
    final newGrantStarted = Completer<void>();
    final releaseNewGrant = Completer<http.Response>();
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/accounts') {
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'One', 'isLive': false},
        ]}), 200);
      }
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      if (request.url.path == '/v1/candles') {
        oldStarted.complete();
        return oldResponse.future;
      }
      if (request.url.path == '/auth/ctrader/redeem') {
        newGrantStarted.complete();
        return releaseNewGrant.future;
      }
      throw StateError('Unexpected broker route ${request.url.path}');
    }));
    final controller = MarketController(storage: storage, api: api);
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await controller.initialize(enableDeepLinks: false);
    final oldRead = controller.history(
        gold, '1m', before: DateTime.utc(2026, 11, 20));
    await oldStarted.future.timeout(const Duration(seconds: 5));
    await storage.write(key: 'tradelab_flutter_oauth_pending', value:
      jsonEncode({'verifier': 'pending-verifier',
        'created': DateTime.now().toUtc().millisecondsSinceEpoch}));
    final linking = controller.completeOAuth(Uri.parse(
        'tradelabflutter://oauth/ctrader?ticket=pending-grant'));
    await newGrantStarted.future.timeout(const Duration(seconds: 5));

    final oldRejected = expectLater(oldRead,
        throwsA(isA<MarketDataException>().having(
          (e) => e.message, 'superseded authorization',
          contains('تفويض'))));
    oldResponse.complete(responseFor(http.Request('GET',
      Uri.parse('https://tradelab-vercel-gateway.vercel.app'
          '/v1/candles?accountId=101&symbolId=42&period=M1')),
      refreshedToken: 'old-replay-token'));
    await oldRejected;
    expect(await storage.read(key: 'tradelab_flutter_ctrader_session'),
        'session-old',
        reason: 'The pending OAuth grant must reject late old-session tokens');
    releaseNewGrant.complete(http.Response(jsonEncode({
      'permission': 'read_only', 'sessionToken': 'session-new',
    }), 200));
    await linking;
    expect(controller.accountId, '101');
    expect(await storage.read(key: 'tradelab_flutter_ctrader_session'),
        'session-new');
  });

  test('401 and malformed broker JSON cannot rotate OAuth credentials',
      () async {
    for (final invalid in <String>['unauthorized', 'malformed']) {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      await storage.write(
          key: 'tradelab_flutter_ctrader_session', value: 'session-safe');
      final api = MarketApi(client: MockClient((request) async {
        if (request.url.path == '/v1/accounts') {
          return http.Response(jsonEncode({'accounts': [
            {'accountId': '101', 'broker': 'A', 'isLive': false},
          ]}), 200);
        }
        if (request.url.path == '/v1/symbols') {
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42},
          ]}), 200);
        }
        expect(request.url.path, '/v1/candles');
        if (invalid == 'unauthorized') {
          return http.Response(jsonEncode({'error': 'session_expired'}), 401,
            headers: {'x-tradelab-session': 'forbidden-old-header'});
        }
        return http.Response('{broken-json', 200,
          headers: {'x-tradelab-session': 'forbidden-broken-header'});
      }));
      final controller = MarketController(storage: storage, api: api);
      try {
        await controller.initialize(enableDeepLinks: false);
        final revision = controller.ctraderAuthorizationRevision;
        await expectLater(
          controller.history(gold, '1m',
              before: DateTime.utc(2026, 11, 20)),
          throwsA(isA<MarketDataException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(await storage.read(key: 'tradelab_flutter_ctrader_session'),
            'session-safe');
        expect(controller.ctraderAuthorizationRevision, revision,
          reason: 'A rejected or corrupted response cannot change auth');
      } finally {
        controller.dispose();
        api.close();
      }
    }
  });

  testWidgets('reselecting same cTrader account invalidates chart generation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'tradelab_flutter_ctrader_session', value: 'session-1');
    var candleRequests = 0;
    final api = MarketApi(client: MockClient((request) async {
      final path = request.url.path;
      if (path == '/v1/accounts') {
        return http.Response(jsonEncode({'accounts': [
          {'accountId': '101', 'broker': 'A', 'isLive': false},
        ]}), 200);
      }
      if (path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      if (path == '/v1/spot') {
        return http.Response(jsonEncode({
          'source': 'ctrader', 'accountId': '101', 'symbolId': '42',
          'bid': 3900, 'ask': 3900.2,
          'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
        }), 200);
      }
      if (path == '/v1/candles') {
        candleRequests++;
        return responseFor(request);
      }
      throw StateError('Unexpected API path: $path');
    }));
    final controller = MarketController(storage: storage, api: api);
    addTearDown(controller.dispose);
    addTearDown(api.close);
    await controller.initialize(enableDeepLinks: false);
    final revisionBefore = controller.ctraderAuthorizationRevision;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TradeLabApp(controller: controller));
    await tester.pumpAndSettle();
    final beforeCount = candleRequests;
    expect(beforeCount, greaterThan(0));
    controller.chooseAccount('101');
    await tester.pumpAndSettle();
    expect(controller.ctraderAuthorizationRevision,
        greaterThan(revisionBefore));
    expect(candleRequests, greaterThan(beforeCount),
      reason: 'Same-number new authorization must replace chart source');
    expect(tester.takeException(), isNull);
  });
}
