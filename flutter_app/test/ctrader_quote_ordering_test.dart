import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_controller.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

/// The same verified XAUUSD source can be requested by both the chart and
/// Markets. Network completion order is NOT quote-timestamp order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MarketController> buildController(
      Future<http.Response> Function() spotResponse) async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'tradelab_flutter_ctrader_session', value: 'test-session');
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/accounts':
          return http.Response(jsonEncode({
            'accounts': [
              {'accountId': '101', 'broker': 'Read Only', 'isLive': false}
            ],
          }), 200);
        case '/v1/symbols':
          return http.Response(jsonEncode({
            'symbols': [{'symbolName': 'XAUUSD', 'symbolId': 42}],
          }), 200);
        case '/v1/spot':
          expect(request.url.queryParameters['accountId'], '101');
          expect(request.url.queryParameters['symbolId'], '42');
          return spotResponse();
        default:
          // Other symbols and Binance are intentionally unavailable here.
          // Their errors must never rewrite a verified XAUUSD price.
          return http.Response('{}', 503);
      }
    });
    final controller = MarketController(
        storage: storage, api: MarketApi(client: client));
    await controller.initialize(enableDeepLinks: false);
    expect(controller.accountId, '101');
    return controller;
  }

  http.Response spot(double bid, int timestamp) => http.Response(jsonEncode({
        'source': 'ctrader',
        'accountId': '101',
        'symbolId': '42',
        'bid': bid,
        'ask': bid + 0.2,
        'timestamp': timestamp,
      }), 200);

  final gold = tradeSymbols.firstWhere((s) => s.code == 'XAUUSD');

  test('late quote cannot replace a newer verified BID/ASK for same account',
      () async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final firstRequest = Completer<void>();
    final olderResponse = Completer<http.Response>();
    var count = 0;
    final controller = await buildController(() {
      count++;
      if (count == 1) {
        firstRequest.complete();
        return olderResponse.future;
      }
      return Future.value(spot(3910, nowMs));
    });
    addTearDown(controller.dispose);

    final oldRequest = controller.paperQuote(gold);
    await firstRequest.future.timeout(const Duration(seconds: 3));
    final newest = await controller.paperQuote(gold);
    expect(newest.bid, 3910);
    expect(controller.recentQuoteFor(gold)!.bid, 3910);

    // The response is well-formed and still within freshness bounds, but
    // arrived out of order. It must never rewind the displayed quote.
    olderResponse.complete(spot(3880, nowMs - 20000));
    final preserved = await oldRequest;
    expect(preserved.bid, 3910);
    expect(preserved.timestampMs, nowMs);
    expect(controller.recentQuoteFor(gold)!.bid, 3910);
    expect(count, 2);
  });

  test('failed Markets refresh cannot erase a newer chart quote',
      () async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final batchReached = Completer<void>();
    final failedBatch = Completer<http.Response>();
    var spotCalls = 0;
    final controller = await buildController(() {
      spotCalls++;
      if (spotCalls == 1) {
        batchReached.complete();
        return failedBatch.future;
      }
      return Future.value(spot(3912, nowMs));
    });
    addTearDown(controller.dispose);

    final batch = controller.refreshQuotes();
    await batchReached.future.timeout(const Duration(seconds: 3));
    final fresh = await controller.paperQuote(gold);
    expect(fresh.bid, 3912);
    failedBatch.complete(http.Response(
        jsonEncode({'error': 'ctrader_broker_unavailable'}), 503));
    await batch;

    expect(controller.recentQuoteFor(gold)!.bid, 3912);
    expect(controller.forexPrices['XAUUSD'], 3912,
        reason: 'A failed older batch may not clear the newer BID');
    expect(controller.loadingQuotes, isFalse);
  });
}
