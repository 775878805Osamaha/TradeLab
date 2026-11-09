import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  test('Flutter login is blocked until compatible gateway version is deployed', () async {
    final old = MarketApi(client: MockClient((_) async =>
      http.Response(jsonEncode({'status':'ok','authEnabled':true}),200)));
    expect(await old.supportsFlutterOAuth(), isFalse);
    final updated = MarketApi(client: MockClient((_) async =>
      http.Response(jsonEncode({'status':'ok','authEnabled':true,
        'flutterOAuthSupported':true}),200)));
    expect(await updated.supportsFlutterOAuth(), isTrue);
  });

  test('Binance candles use public Binance endpoint and reject open candles', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      return http.Response(jsonEncode([
        [1000, '100', '102', '99', '101', '7', 1999],
        [2000, '101', '104', '100', '103', '3', 2999],
      ]), 200);
    });
    final api = MarketApi(client: client);
    final bars = await api.binanceCandles(symbol: 'BTCUSDT', timeframe: '15m',
      before: DateTime.fromMillisecondsSinceEpoch(2200, isUtc: true));
    expect(bars.length, 1);
    expect(bars.single.candle.close, 101);
  });

  test('forbids unapproved Binance symbols', () async {
    final api = MarketApi(client: MockClient((_) async => http.Response('[]', 200)));
    expect(() => api.binanceCandles(symbol: 'XAUUSD', timeframe: '15m'),
        throwsA(isA<MarketDataException>()));
  });

  test('rejects corrupted OHLC and backward broker timestamps', () {
    expect(() => parseVerifiedBars([
      {'timestamp': 1500, 'open': 100, 'high': 101, 'low': 98, 'close': 100},
      {'timestamp': 1400, 'open': 100, 'high': 101, 'low': 98, 'close': 100},
    ], sourceType: TradeSource.ctrader, minTime: 1000, maxTime: 2000),
        throwsA(isA<MarketDataException>()));
    expect(() => validateBars([const MarketBar(1, TradeCandle(101, 102, 100, 103))]),
        throwsA(isA<MarketDataException>()));
  });

  test('cTrader M1 requests bounded recent closed candles only', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final lastClosedMinute =
        (now ~/ 60000) * 60000 - 60000;
    final seen = <Uri>[];
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42}
        ]}), 200);
      }
      seen.add(request.url);
      expect(request.url.path, '/v1/candles');
      expect(request.url.queryParameters['period'], 'M1');
      expect(request.url.queryParameters['symbolId'], '42');
      final from = int.parse(request.url.queryParameters['from']!);
      final to = int.parse(request.url.queryParameters['to']!);
      expect(to - from, 900 * 60000);
      expect(to % 60000, 59999);
      expect(to, lessThan(now));
      return http.Response(jsonEncode({
        'source': 'ctrader', 'period': 'M1', 'symbolId': '42',
        'accountId': '7',
        'hasMore': false,
        'candles': [
          {'timestamp': lastClosedMinute, 'open': 4110.0,
           'high': 4111.0, 'low': 4109.0, 'close': 4110.5},
        ],
      }), 200);
    });
    final api = MarketApi(client: client);
    final candles = await api.ctraderCandles(
      token: 'test', accountId: '7', symbol: 'XAUUSD',
      timeframe: '1m', before: DateTime.now().toUtc(),
    );
    expect(candles, hasLength(1));
    expect(candles.single.timestamp, lastClosedMinute);
    expect(seen, hasLength(1));
  });

  test('cTrader M1 rejects another authorized broker account', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final closed = (now ~/ 60000) * 60000 - 60000;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42}
        ]}), 200);
      }
      return http.Response(jsonEncode({
        'source': 'ctrader', 'period': 'M1', 'symbolId': '42',
        // A legitimate feed from a different account must be rejected.
        'accountId': '8', 'hasMore': false,
        'candles': [
          {'timestamp': closed, 'open': 4110.0,
           'high': 4111.0, 'low': 4109.0, 'close': 4110.5},
        ],
      }), 200);
    });
    final api = MarketApi(client: client);
    await expectLater(api.ctraderCandles(
      token: 'test', accountId: '7', symbol: 'XAUUSD',
      timeframe: '1m', before: DateTime.now().toUtc(),
    ), throwsA(isA<MarketDataException>()));
  });

  test('cTrader M1 refuses incomplete pages or active-minute candles',
      () async {
    for (final mode in ['truncated', 'forming']) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final activeMinute = (now ~/ 60000) * 60000;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/symbols') {
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42}
          ]}), 200);
        }
        return http.Response(jsonEncode({
          'source': 'ctrader', 'period': 'M1', 'symbolId': '42',
        'accountId': '7',
          'hasMore': mode == 'truncated',
          'candles': [
            {'timestamp': activeMinute, 'open': 4110.0,
             'high': 4110.5, 'low': 4109.5, 'close': 4110.2}
          ],
        }), 200);
      });
      final api = MarketApi(client: client);
      await expectLater(
        api.ctraderCandles(token:'test', accountId:'7',
          symbol:'XAUUSD', timeframe:'1m',
          before:DateTime.now().toUtc()),
        throwsA(isA<MarketDataException>()),
      );
    }
  });

  test('cTrader rejects unverified source even for correctly shaped bars', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42, 'archived': false},
        ]}), 200);
      }
      return http.Response(jsonEncode({'source':'fabricated', 'period':'M15',
        'symbolId':'42', 'candles': []}), 200);
    });
    final api = MarketApi(client: client);
    expect(() => api.ctraderCandles(token:'secret', accountId:'1',
        symbol:'XAUUSD', timeframe:'15m', before:DateTime.utc(2026, 11, 8)),
        throwsA(isA<MarketDataException>()));
  });

  test('cTrader does not build range candles from incomplete tick pages', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      return http.Response(jsonEncode({'source':'ctrader', 'quoteType':'bid',
        'symbolId':'42', 'hasMore':true, 'ticks': []}), 200);
    });
    final api = MarketApi(client: client);
    expect(() => api.ctraderBidTicks(token:'secret', accountId:'1',
        symbol:'XAUUSD', before:DateTime.utc(2026, 11, 8)),
        throwsA(isA<MarketDataException>()));
  });

  test('cTrader fills truncated tick pages by splitting exact milliseconds',
      () async {
    final end = DateTime.utc(2026, 11, 8).millisecondsSinceEpoch;
    final start = end - const Duration(days: 6).inMilliseconds;
    final middle = start + (end - start) ~/ 2;
    final intervals = <(int, int)>[];
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/ticks');
      final from = int.parse(request.url.queryParameters['from']!);
      final to = int.parse(request.url.queryParameters['to']!);
      intervals.add((from, to));
      if (from == start && to == end) {
        return http.Response(jsonEncode({
          'source': 'ctrader', 'quoteType': 'bid',
          'symbolId': '42', 'hasMore': true, 'ticks': [],
        }), 200);
      }
      final rows = from == start && to == middle
          ? [
              {'timestamp': middle, 'price': 1900.1},
              {'timestamp': middle, 'price': 1900.2},
            ]
          : [
              {'timestamp': middle + 1, 'price': 1900.3},
              {'timestamp': middle + 1, 'price': 1900.4},
            ];
      return http.Response(jsonEncode({
        'source': 'ctrader', 'quoteType': 'bid',
        'symbolId': '42', 'hasMore': false, 'ticks': rows,
      }), 200);
    });
    final api = MarketApi(client: client);
    final ticks = await api.ctraderBidTicks(
      token: 'secret', accountId: '1', symbol: 'XAUUSD',
      before: DateTime.fromMillisecondsSinceEpoch(end, isUtc: true),
    );
    expect(intervals, [
      (start, end),
      (start, middle),
      (middle + 1, end),
    ]);
    expect(ticks.map((tick) => tick.timestamp).toList(),
        [middle, middle, middle + 1, middle + 1]);
    expect(ticks.map((tick) => tick.bid).toList(),
        [1900.1, 1900.2, 1900.3, 1900.4]);
  });

  test('incremental BID refresh requests exactly the missing milliseconds',
      () async {
    final toMs = DateTime.utc(2026, 11, 8).millisecondsSinceEpoch;
    final fromMs = toMs - const Duration(minutes: 5).inMilliseconds;
    var brokerCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      brokerCalls++;
      expect(request.url.path, '/v1/ticks');
      expect(request.url.queryParameters['from'], '$fromMs');
      expect(request.url.queryParameters['to'], '$toMs');
      return http.Response(jsonEncode({
        'source': 'ctrader', 'quoteType': 'bid',
        'symbolId': '42', 'hasMore': false, 'ticks': [
          {'timestamp': fromMs, 'price': 2000.0},
          {'timestamp': fromMs, 'price': 2000.1},
          {'timestamp': toMs, 'price': 2000.2},
        ],
      }), 200);
    });
    final api = MarketApi(client: client);
    final ticks = await api.ctraderBidTicksRange(
      token: 'secret', accountId: '1', symbol: 'XAUUSD',
      fromMs: fromMs, toMs: toMs);
    expect(brokerCalls, 1);
    expect(ticks.map((tick) => tick.bid).toList(),
        [2000.0, 2000.1, 2000.2]);
  });

  test('incremental BID requests reject invalid or oversized windows', () async {
    final api = MarketApi(client: MockClient((_) async =>
        fail('Invalid BID window should never reach a provider')));
    await expectLater(
      api.ctraderBidTicksRange(token: 'secret', accountId: '1',
        symbol: 'XAUUSD', fromMs: 300, toMs: 299),
      throwsA(isA<MarketDataException>()),
    );
    await expectLater(
      api.ctraderBidTicksRange(token: 'secret', accountId: '1',
        symbol: 'XAUUSD', fromMs: 1,
        toMs: 1 + const Duration(days: 7).inMilliseconds),
      throwsA(isA<MarketDataException>()),
    );
  });

  test('cTrader symbol metadata is reused for repeated market requests and reset safely', () async {
    var symbolRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        symbolRequests++;
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/spot');
      expect(request.url.queryParameters['symbolId'], '42');
      return http.Response(jsonEncode({
        'source': 'ctrader', 'symbolId': '42', 'timestamp': 1700000000000,
        'bid': 2000, 'ask': 2000.2,
      }), 200);
    });
    final api = MarketApi(client: client);
    expect(await api.ctraderBid(token: 'token', accountId: '1', symbol: 'XAUUSD'), 2000);
    expect(await api.ctraderBid(token: 'token', accountId: '1', symbol: 'XAUUSD'), 2000);
    expect(symbolRequests, 1);
    api.forgetCTraderSymbols();
    expect(await api.ctraderBid(token: 'token', accountId: '1', symbol: 'XAUUSD'), 2000);
    expect(symbolRequests, 2);
  });

  test('parallel forex quotes share one authorized broker symbol-list request', () async {
    var symbolRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        symbolRequests++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
          {'symbolName': 'EURUSD', 'symbolId': 43},
        ]}), 200);
      }
      final id = request.url.queryParameters['symbolId'];
      return http.Response(jsonEncode({
        'source': 'ctrader', 'symbolId': id, 'timestamp': 1700000000000,
        'bid': 1.25, 'ask': 1.26,
      }), 200);
    });
    final api = MarketApi(client: client);
    final quotes = await Future.wait([
      api.ctraderBid(token: 'token', accountId: '1', symbol: 'XAUUSD'),
      api.ctraderBid(token: 'token', accountId: '1', symbol: 'EURUSD'),
    ]);
    expect(quotes, [1.25, 1.25]);
    expect(symbolRequests, 1);
  });

  test('Binance paper quote uses verified bid/ask, never last-trade ticker', () async {
    final api = MarketApi(client: MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/ticker/bookTicker');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      return http.Response(jsonEncode({
        'symbol': 'BTCUSDT', 'bidPrice': '105.5', 'askPrice': '106.2',
      }), 200);
    }));
    final quoted = await api.binanceQuote('BTCUSDT');
    expect(quoted.bid, 105.5);
    expect(quoted.ask, 106.2);
    expect(quoted.executionPrice(buy: true), 106.2);
    expect(quoted.executionPrice(buy: false), 105.5);
    quoted.assertFresh(nowMs: DateTime.now().toUtc().millisecondsSinceEpoch);
  });

  test('Binance paper quote rejects crossed and tampered prices', () async {
    final api = MarketApi(client: MockClient((_) async =>
      http.Response(jsonEncode({
        'symbol': 'BTCUSDT', 'bidPrice': '120', 'askPrice': '110',
      }), 200)));
    await expectLater(api.binanceQuote('BTCUSDT'),
      throwsA(isA<MarketDataException>()));
  });
}
