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

  test('Binance native 2h uses verified klines and excludes unclosed bar',
      () async {
    const end = 15000000;
    final api = MarketApi(client: MockClient((request) async {
      expect(request.url.host, 'api.binance.com');
      expect(request.url.path, '/api/v3/klines');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      expect(request.url.queryParameters['interval'], '2h');
      expect(request.url.queryParameters['endTime'], '${end - 1}');
      return http.Response(jsonEncode([
        [0, '100', '104', '98', '102', '7', 7199999],
        [7200000, '102', '107', '101', '105', '5', 14399999],
        [14400000, '105', '108', '103', '107', '2', 21599999],
      ]), 200);
    }));
    final bars = await api.binanceCandles(
      symbol: 'BTCUSDT', timeframe: '2h',
      before: DateTime.fromMillisecondsSinceEpoch(end, isUtc: true),
    );
    expect(bars, hasLength(2));
    expect(bars.first.timestamp, 0);
    expect(bars.last.timestamp, 7200000);
    expect(bars.last.candle.close, 105);
  });

  test('Binance candles reject fractional open or close timestamps', () async {
    for (final window in <(num, num)>[
      (1000.5, 1999),
      (1000, 1999.5),
      (1000, 1000),
      (2000, 1999),
    ]) {
      final api = MarketApi(client: MockClient((request) async {
        expect(request.url.host, 'api.binance.com');
        return http.Response(jsonEncode([
          [window.$1, '100', '102', '99', '101', '7', window.$2],
        ]), 200);
      }));
      await expectLater(
        api.binanceCandles(
          symbol: 'BTCUSDT', timeframe: '1m',
          before: DateTime.fromMillisecondsSinceEpoch(4000, isUtc: true),
        ),
        throwsA(isA<MarketDataException>()),
      );
      api.close();
    }
  });

  test('cTrader live quote refuses a fractional provider timestamp', () async {
    const ms = 1700000000000;
    for (final badTimestamp in <Object>[ms + .75, '1700000000000']) {
      final api = MarketApi(client: MockClient((request) async {
        if (request.url.path == '/v1/symbols') {
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42},
          ]}), 200);
        }
        expect(request.url.path, '/v1/spot');
        return http.Response(jsonEncode({
          'source': 'ctrader', 'symbolId': '42',
          'timestamp': badTimestamp, 'bid': 2000.0, 'ask': 2000.2,
        }), 200);
      }));
      await expectLater(
        api.ctraderQuote(token: 'test', accountId: '1', symbol: 'XAUUSD'),
        throwsA(isA<MarketDataException>()),
      );
      api.close();
    }

    final validApi = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      return http.Response(jsonEncode({
        'source': 'ctrader', 'symbolId': '42',
        'timestamp': 1700000000000.0, 'bid': 2000.0, 'ask': 2000.2,
      }), 200);
    }));
    final quote = await validApi.ctraderQuote(
        token: 'test', accountId: '1', symbol: 'XAUUSD');
    expect(quote.timestampMs, ms);
    expect(quote.bid, 2000);
    validApi.close();
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
      expect(request.url.queryParameters['count'], '900');
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

  test('cTrader never requests still-forming daily, weekly or monthly bars',
      () async {
    final now = DateTime.now().toUtc();
    final cutoffByPeriod = {
      'D1': DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch - 1,
      'W1': DateTime.utc(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday))
          .millisecondsSinceEpoch - 1,
      'MN1': DateTime.utc(now.year, now.month).millisecondsSinceEpoch - 1,
    };
    final requested = <String, int>{};
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/candles');
      final period = request.url.queryParameters['period']!;
      final to = int.parse(request.url.queryParameters['to']!);
      expect(to, lessThanOrEqualTo(cutoffByPeriod[period]!));
      requested[period] = to;
      return http.Response(jsonEncode({
        'source': 'ctrader', 'period': period, 'symbolId': '42',
        'accountId': '7', 'hasMore': false, 'candles': [],
      }), 200);
    }));
    for (final timeframe in ['1D', '1W', '1M']) {
      final bars = await api.ctraderCandles(
        token: 'test', accountId: '7', symbol: 'XAUUSD',
        timeframe: timeframe, before: now.add(const Duration(days: 40)),
      );
      expect(bars, isEmpty);
    }
    expect(requested.keys.toSet(), {'D1', 'W1', 'MN1'});
  });

  test('cTrader reports unusable provider OHLC distinctly from bad requests',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42}
        ]}), 200);
      }
      return http.Response(
        jsonEncode({'error': 'ctrader_candle_history_unusable'}), 502,
      );
    });
    final api = MarketApi(client: client);
    await expectLater(
      api.ctraderCandles(token: 'test', accountId: '7',
        symbol: 'XAUUSD', timeframe: '1m',
        before: DateTime.now().toUtc()),
      throwsA(isA<MarketDataException>().having(
        (error) => error.message, 'message',
        contains('شموع غير متسقة'))),
    );
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

  test('verified truncated cTrader page is shown and older pages use an exclusive cursor',
      () async {
    const step = 15 * 60000;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final latestClosed = (now ~/ step) * step - step;
    final earlier = latestClosed - step;
    final requests = <Uri>[];
    Map<String, Object> bar(int timestamp) => {
      'timestamp': timestamp, 'open': 4110.0,
      'high': 4111.0, 'low': 4109.0, 'close': 4110.5,
    };
    final client = MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/candles');
      expect(request.url.queryParameters['period'], 'M15');
      requests.add(request.url);
      return http.Response(jsonEncode({
        'source': 'ctrader', 'period': 'M15',
        'symbolId': '42', 'accountId': '7',
        'hasMore': requests.length == 1,
        'candles': requests.length == 1
            ? [bar(earlier), bar(latestClosed)]
            : [bar(earlier - step)],
      }), 200);
    });
    final api = MarketApi(client: client);
    final visible = await api.ctraderCandles(
      token: 'test', accountId: '7', symbol: 'XAUUSD',
      timeframe: '15m', before: DateTime.now().toUtc(),
    );
    expect(visible.map((bar) => bar.timestamp).toList(),
        [earlier, latestClosed]);

    final older = await api.ctraderCandles(
      token: 'test', accountId: '7', symbol: 'XAUUSD',
      timeframe: '15m',
      before: DateTime.fromMillisecondsSinceEpoch(earlier - 1, isUtc: true),
    );
    expect(older.map((bar) => bar.timestamp).toList(), [earlier - step]);
    expect(int.parse(requests.last.queryParameters['to']!), earlier - 1);
    expect(requests, hasLength(2));
  });

  test('cTrader rejects truncated pages without a valid history cursor',
      () async {
    for (final mode in ['empty', 'malformed']) {
      final client = MockClient((request) async {
        if (request.url.path == '/v1/symbols') {
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42},
          ]}), 200);
        }
        return http.Response(jsonEncode({
          'source': 'ctrader', 'period': 'M15',
          'symbolId': '42', 'accountId': '7',
          'hasMore': mode == 'empty' ? true : 'true',
          'candles': [],
        }), 200);
      });
      final api = MarketApi(client: client);
      await expectLater(api.ctraderCandles(
        token: 'test', accountId: '7', symbol: 'XAUUSD',
        timeframe: '15m', before: DateTime.now().toUtc(),
      ), throwsA(isA<MarketDataException>()));
    }
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

  test('cTrader tick errors explain broker rejection and failed transport',
      () async {
    for (final item in const [
      ('ctrader_tick_history_unusable', 'غير مكتملة'),
      ('ctrader_broker_rejected_request', 'رفض وسيط'),
      ('ctrader_response_timeout', 'مهلة'),
      ('ctrader_connection_failed', 'اتصال'),
    ]) {
      final api = MarketApi(client: MockClient((request) async {
        if (request.url.path == '/v1/symbols') {
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42}
          ]}), 200);
        }
        expect(request.url.path, '/v1/ticks');
        return http.Response(jsonEncode({'error': item.$1}), 503);
      }));
      await expectLater(
        api.ctraderBidTicksRange(
          token: 'fake', accountId: '1', symbol: 'XAUUSD',
          fromMs: 1700000000000, toMs: 1700003600000,
        ),
        throwsA(isA<MarketDataException>().having(
          (error) => error.message, 'message', contains(item.$2))),
      );
    }
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

  test('bounded concurrent BID splits preserve same-ms events and time order',
      () async {
    const start = 1700000000000;
    const end = start + 7;
    var active = 0;
    var maximumActive = 0;
    var requestCount = 0;
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/ticks');
      requestCount++;
      active++;
      if (active > maximumActive) maximumActive = active;
      final from = int.parse(request.url.queryParameters['from']!);
      final to = int.parse(request.url.queryParameters['to']!);
      try {
        // Older and newer halves complete in deliberately different orders.
        await Future<void>.delayed(
            Duration(milliseconds: from == start ? 15 : 2));
        if (to - from > 1) {
          return http.Response(jsonEncode({
            'source': 'ctrader', 'quoteType': 'bid',
            'symbolId': '42', 'hasMore': true, 'ticks': [],
          }), 200);
        }
        final price = 1900.0 + (to - start);
        return http.Response(jsonEncode({
          'source': 'ctrader', 'quoteType': 'bid',
          'symbolId': '42', 'hasMore': false,
          'ticks': [
            {'timestamp': to, 'price': price},
            {'timestamp': to, 'price': price + 0.1},
          ],
        }), 200);
      } finally {
        active--;
      }
    }));
    final ticks = await api.ctraderBidTicksRange(
      token: 'fake', accountId: '1', symbol: 'XAUUSD',
      fromMs: start, toMs: end,
    );
    expect(requestCount, 7);
    expect(maximumActive, 2,
        reason: 'Only two cTrader pages may be in flight');
    expect(ticks.map((tick) => tick.timestamp), [
      start + 1, start + 1, start + 3, start + 3,
      start + 5, start + 5, start + 7, start + 7,
    ]);
    expect(ticks.map((tick) => tick.bid), [
      1901.0, 1901.1, 1903.0, 1903.1,
      1905.0, 1905.1, 1907.0, 1907.1,
    ]);
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

  test('dense cTrader BID JSON is decoded off the UI isolate in original order',
      () async {
    const fromMs = 1700000000000;
    final ticks = List<Map<String, Object>>.generate(6000, (index) => {
      // Multiple authentic events in a millisecond must not be coalesced.
      'timestamp': fromMs + index ~/ 2,
      'price': 2000.0 + index * 0.0001,
    });
    final body = jsonEncode({
      'source': 'ctrader',
      'quoteType': 'bid',
      'symbolId': '42',
      'hasMore': false,
      'ticks': ticks,
    });
    expect(MarketJsonDecodePolicy.shouldOffload(
        path: '/v1/ticks', chars: body.length), isTrue);
    expect(MarketJsonDecodePolicy.shouldOffload(
        path: '/v1/candles', chars: body.length), isFalse);
    expect(MarketJsonDecodePolicy.shouldOffload(
        path: '/v1/ticks', chars: 100), isFalse);
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/ticks');
      return http.Response(body, 200);
    }));
    final parsed = await api.ctraderBidTicksRange(
      token: 'fake', accountId: '1', symbol: 'XAUUSD',
      fromMs: fromMs, toMs: fromMs + 6000,
    );
    expect(parsed, hasLength(ticks.length));
    expect(parsed.first.timestamp, fromMs);
    expect(parsed[1].timestamp, fromMs);
    expect(parsed.last.timestamp, fromMs + 2999);
    expect(parsed.last.bid, closeTo(2000.0 + 5999 * 0.0001, 1e-9));
  });

  test('dense BID worker rejects corrupted source price without partial bars',
      () async {
    const start = 1700000000000;
    final rows = List<Map<String, Object>>.generate(6000, (index) =>
        {'timestamp': start + index, 'price': 2100.0 + index / 10000});
    for (final corruption in <Object>[-1.0, 'not-a-bid-price']) {
      rows[5700]['price'] = corruption;
      final body = jsonEncode({
        'source': 'ctrader',
        'quoteType': 'bid', 'symbolId': '42', 'hasMore': false,
        'ticks': rows,
      });
      expect(MarketJsonDecodePolicy.shouldOffload(
          path: '/v1/ticks', chars: body.length), isTrue);
      final api = MarketApi(client: MockClient((request) async {
        if (request.url.path == '/v1/symbols') {
          return http.Response(jsonEncode({'symbols': [
            {'symbolName': 'XAUUSD', 'symbolId': 42},
          ]}), 200);
        }
        expect(request.url.path, '/v1/ticks');
        return http.Response(body, 200);
      }));
      await expectLater(
        api.ctraderBidTicksRange(
          token: 'test', accountId: '1', symbol: 'XAUUSD',
          fromMs: start, toMs: start + 7000,
        ),
        throwsA(isA<MarketDataException>()),
      );
      api.close();
    }
  });

  test('verified cTrader OHLC rejects fractional broker milliseconds', () {
    const start = 1700000000000;
    for (final badTime in <Object>[start + .5, '1700000000000']) {
      expect(
        () => parseVerifiedBars([
          {'timestamp': badTime, 'open': 1900.0, 'high': 1901.0,
            'low': 1899.0, 'close': 1900.5},
        ], sourceType: TradeSource.ctrader,
          minTime: start - 1000, maxTime: start + 1000),
        throwsA(isA<MarketDataException>()),
      );
    }
    final valid = parseVerifiedBars([
      {'timestamp': 1700000000000.0, 'open': 1900.0, 'high': 1901.0,
       'low': 1899.0, 'close': 1900.5},
    ], sourceType: TradeSource.ctrader,
      minTime: start - 1000, maxTime: start + 1000);
    expect(valid.single.timestamp, start,
        reason: 'Only exactly whole milliseconds may be accepted');
  });

  test('small BID page rejects fractional milliseconds rather than truncating',
      () async {
    const start = 1700000000000;
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/ticks');
      return http.Response(jsonEncode({
        'source': 'ctrader', 'quoteType': 'bid', 'symbolId': '42',
        'hasMore': false, 'ticks': [
          {'timestamp': start + .75, 'price': 2000.25},
        ],
      }), 200);
    }));
    await expectLater(
      api.ctraderBidTicksRange(
          token: 'test', accountId: '1', symbol: 'XAUUSD',
          fromMs: start, toMs: start + 1000),
      throwsA(isA<MarketDataException>()),
    );
    api.close();
  });

  test('dense BID worker rejects fractional timestamps without changing order',
      () async {
    const start = 1700000000000;
    final entries = List<Map<String, Object>>.generate(6000, (index) => {
      'timestamp': start + index,
      'price': 2100.0 + index / 100000,
    });
    entries[5700]['timestamp'] = start + 5700.5;
    final body = jsonEncode({
      'source': 'ctrader', 'quoteType': 'bid', 'symbolId': '42',
      'hasMore': false, 'ticks': entries,
    });
    expect(MarketJsonDecodePolicy.shouldOffload(
        path: '/v1/ticks', chars: body.length), isTrue);
    final api = MarketApi(client: MockClient((request) async {
      if (request.url.path == '/v1/symbols') {
        return http.Response(jsonEncode({'symbols': [
          {'symbolName': 'XAUUSD', 'symbolId': 42},
        ]}), 200);
      }
      expect(request.url.path, '/v1/ticks');
      return http.Response(body, 200);
    }));
    await expectLater(
      api.ctraderBidTicksRange(
          token: 'test', accountId: '1', symbol: 'XAUUSD',
          fromMs: start, toMs: start + 7000),
      throwsA(isA<MarketDataException>()),
    );
    api.close();
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
