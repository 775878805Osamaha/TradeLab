import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
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
}
