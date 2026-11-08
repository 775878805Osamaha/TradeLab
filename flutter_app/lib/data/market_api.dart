import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tradelab_data.dart';

/// The only permitted providers: cTrader for forex/gold, Binance for crypto.
/// No demo, fallback feed, or OHLC-derived ticks are permitted here.
class MarketApi {
  MarketApi({http.Client? client, this.gateway = 'https://tradelab-vercel-gateway.vercel.app',
    this.onSessionRefresh}) : _client = client ?? http.Client();

  final http.Client _client;
  final String gateway;
  final void Function(String)? onSessionRefresh;

  void close() => _client.close();

  Future<Map<String, dynamic>> _json(Uri url, {String? token, Object? body}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (body != null) headers['Content-Type'] = 'application/json';
    final http.Response response;
    try {
      response = body == null
          ? await _client.get(url, headers: headers).timeout(const Duration(seconds: 22))
          : await _client.post(url, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 22));
    } catch (_) {
      throw const MarketDataException('تعذر الوصول إلى مصدر السوق. تحقق من الإنترنت وأعد المحاولة.');
    }
    final refreshed = response.headers['x-tradelab-session'];
    if (refreshed != null && refreshed.isNotEmpty) onSessionRefresh?.call(refreshed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw const MarketDataException('انتهت جلسة cTrader. أعد ربط الحساب.', sessionExpired: true);
      }
      throw MarketDataException('فشل الاتصال بالمصدر (${response.statusCode}). أعد المحاولة.');
    }
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } catch (_) {
      throw const MarketDataException('أعاد مصدر السوق استجابة غير صالحة.');
    }
  }

  Uri _gateway(String path, Map<String, String> query) =>
      Uri.parse(gateway).replace(path: path, queryParameters: query.isEmpty ? null : query);

  Future<String> redeem({required String ticket, required String verifier}) async {
    final data = await _json(_gateway('/auth/ctrader/redeem', {}),
      body: {'ticket': ticket, 'verifier': verifier});
    if (data['permission'] != 'read_only' || data['sessionToken'] is! String ||
        (data['sessionToken'] as String).isEmpty) {
      throw const MarketDataException('لم يتم تأكيد صلاحية القراءة فقط من cTrader.');
    }
    return data['sessionToken'] as String;
  }

  Future<List<CTraderAccount>> accounts(String token) async {
    final data = await _json(_gateway('/v1/accounts', {}), token: token);
    final entries = data['accounts'];
    if (entries is! List) throw const MarketDataException('قائمة حسابات cTrader غير صالحة.');
    return entries.map((item) {
      if (item is! Map || !RegExp(r'^[1-9][0-9]*$').hasMatch('${item['accountId']}')) {
        throw const MarketDataException('بيانات حساب cTrader غير صالحة.');
      }
      return CTraderAccount('${item['accountId']}', '${item['broker'] ?? ''}', item['isLive'] == true);
    }).toList(growable: false);
  }

  Future<int> symbolId({required String token, required String accountId,
    required String symbol}) async {
    final data = await _json(_gateway('/v1/symbols', {'accountId': accountId}), token: token);
    final entries = data['symbols'];
    if (entries is! List) throw const MarketDataException('قائمة رموز cTrader غير صالحة.');
    for (final item in entries) {
      if (item is! Map || item['archived'] == true) continue;
      final name = (item['symbolName'] ?? item['name'])?.toString().toUpperCase().replaceAll('/', '');
      final id = int.tryParse('${item['symbolId']}');
      if (name == symbol.toUpperCase() && id != null && id > 0) return id;
    }
    throw MarketDataException('رمز $symbol غير متاح لدى وسيط حساب cTrader المحدد.');
  }

  Future<List<MarketBar>> ctraderCandles({required String token, required String accountId,
    required String symbol, required String timeframe, required DateTime before}) async {
    final period = switch (timeframe) {
      '1m' => 'M1', '3m' => 'M3', '5m' => 'M5', '15m' => 'M15',
      '30m' => 'M30', '1h' => 'H1', '4h' => 'H4', '1D' => 'D1',
      '1W' => 'W1', '1M' => 'MN1', _ => throw const MarketDataException('إطار زمني غير مدعوم'),
    };
    final id = await symbolId(token: token, accountId: accountId, symbol: symbol);
    final end = before.toUtc().millisecondsSinceEpoch;
    // The gateway rejects windows wider than 90 days. More pages are fetched as
    // the user scrolls back; an empty page means the broker has no older data.
    final start = end - const Duration(days: 89).inMilliseconds;
    final data = await _json(_gateway('/v1/candles', {
      'accountId': accountId, 'symbolId': '$id', 'period': period,
      'from': '$start', 'to': '$end', 'count': '1000',
    }), token: token);
    if (data['source'] != 'ctrader' || data['period'] != period ||
        '${data['symbolId']}' != '$id') {
      throw const MarketDataException('لم يتم التحقق من مصدر شموع cTrader.');
    }
    return parseVerifiedBars(data['candles'], sourceType: TradeSource.ctrader,
      minTime: start, maxTime: end);
  }

  Future<List<MarketTick>> ctraderBidTicks({required String token, required String accountId,
    required String symbol, required DateTime before}) async {
    final id = await symbolId(token: token, accountId: accountId, symbol: symbol);
    final end = before.toUtc().millisecondsSinceEpoch;
    final start = end - const Duration(days: 6).inMilliseconds;
    final data = await _json(_gateway('/v1/ticks', {
      'accountId': accountId, 'symbolId': '$id', 'from': '$start', 'to': '$end',
    }), token: token);
    if (data['source'] != 'ctrader' || data['quoteType'] != 'bid' ||
        '${data['symbolId']}' != '$id' || data['hasMore'] == true) {
      throw const MarketDataException('تيكات cTrader غير مكتملة؛ لن نكوّن شموع مدى مضللة.');
    }
    final ticks = data['ticks'];
    if (ticks is! List) throw const MarketDataException('تيكات cTrader غير صالحة.');
    final result = <MarketTick>[];
    var previous = start;
    for (final entry in ticks) {
      if (entry is! Map) throw const MarketDataException('تيكات cTrader غير صالحة.');
      final time = (entry['timestamp'] as num?)?.toInt();
      final price = (entry['price'] as num?)?.toDouble();
      if (time == null || time < start || time > end || time < previous ||
          price == null || !price.isFinite || price <= 0) {
        throw const MarketDataException('ترتيب تيكات cTrader أو أسعارها غير صالح.');
      }
      result.add(MarketTick(time, price));
      previous = time;
    }
    return result;
  }

  Future<double> ctraderPointSize({required String token, required String accountId,
    required String symbol}) async {
    final id = await symbolId(token: token, accountId: accountId, symbol: symbol);
    final data = await _json(_gateway('/v1/symbol-detail', {
      'accountId': accountId, 'symbolId': '$id',
    }), token: token);
    if (data['source'] != 'ctrader') {
      throw const MarketDataException('تعذر التحقق من دقة تسعير cTrader.');
    }
    final digits = (data['digits'] as num?)?.toInt();
    if (digits == null || digits < 0 || digits > 10) {
      throw const MarketDataException('دقة تسعير الرمز غير متاحة من cTrader.');
    }
    var point = 1.0;
    for (var i = 0; i < digits; i++) {point /= 10;}
    return point;
  }

  Future<List<MarketBar>> binanceCandles({required String symbol,
    required String timeframe, int limit = 500, DateTime? before}) async {
    if (!const {'BTCUSDT', 'ETHUSDT'}.contains(symbol)) {
      throw const MarketDataException('هذا الرمز ليس ضمن رموز Binance المعتمدة.');
    }
    final interval = switch (timeframe) {
      '1m' => '1m', '3m' => '3m', '5m' => '5m', '15m' => '15m',
      '30m' => '30m', '1h' => '1h', '4h' => '4h', '1D' => '1d',
      '1W' => '1w', '1M' => '1M', _ => throw const MarketDataException('إطار زمني غير مدعوم'),
    };
    final uri = Uri.https('api.binance.com', '/api/v3/klines', {
      'symbol': symbol, 'interval': interval, 'limit': '${limit.clamp(1, 1000)}',
      if (before != null) 'endTime': '${before.toUtc().millisecondsSinceEpoch - 1}',
    });
    final http.Response response;
    try {response = await _client.get(uri).timeout(const Duration(seconds: 20));}
    catch (_) {throw const MarketDataException('تعذر الاتصال بـBinance. تحقق من الإنترنت.');}
    if (response.statusCode != 200) throw MarketDataException('Binance لا يستجيب (${response.statusCode}).');
    try {
      final rows = jsonDecode(response.body);
      if (rows is! List) throw const FormatException();
      final end = (before ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
      final bars = rows.map((row) {
        if (row is! List || row.length < 7) throw const FormatException();
        final ts = (row[0] as num).toInt();
        final closeAt = (row[6] as num).toInt();
        // Exclude the current, unclosed candle to keep Replay look-ahead-free.
        if (closeAt >= end) return null;
        return MarketBar(ts, TradeCandle(double.parse('${row[1]}'), double.parse('${row[2]}'),
          double.parse('${row[3]}'), double.parse('${row[4]}')));
      }).whereType<MarketBar>().toList(growable: false);
      validateBars(bars);
      return bars;
    } catch (_) {throw const MarketDataException('أعادت Binance شموعًا غير صالحة.');}
  }

  Future<double> binancePrice(String symbol) async {
    if (!const {'BTCUSDT', 'ETHUSDT'}.contains(symbol)) throw const MarketDataException('رمز غير مدعوم');
    final data = await _json(Uri.https('api.binance.com', '/api/v3/ticker/price', {'symbol':symbol}));
    if (data['symbol'] != symbol) throw const MarketDataException('مصدر السعر أو رمزه غير متطابق.');
    final price = double.tryParse('${data['price']}');
    if (price == null || !price.isFinite || price <= 0) throw const MarketDataException('سعر Binance غير صالح.');
    return price;
  }
}

class MarketDataException implements Exception {
  const MarketDataException(this.message, {this.sessionExpired = false});
  final String message;
  final bool sessionExpired;
  @override
  String toString() => message;
}

class CTraderAccount {
  const CTraderAccount(this.id, this.broker, this.isLive);
  final String id;
  final String broker;
  final bool isLive;
}

class MarketTick {
  const MarketTick(this.timestamp, this.bid);
  final int timestamp;
  final double bid;
}

class MarketBar {
  const MarketBar(this.timestamp, this.candle);
  final int timestamp;
  final TradeCandle candle;
}

List<MarketBar> parseVerifiedBars(dynamic source, {required TradeSource sourceType,
    required int minTime, required int maxTime}) {
  // The provenance is provided by the validated caller, never by an arbitrary
  // payload field. It remains part of the API contract for future feed types.
  if (sourceType != TradeSource.ctrader && sourceType != TradeSource.binance) {
    throw const MarketDataException('مصدر سوق غير معروف.');
  }
  if (source is! List) throw const MarketDataException('الشموع المستلمة غير صالحة.');
  final bars = source.map((item) {
    if (item is! Map) throw const MarketDataException('الشموع المستلمة غير صالحة.');
    final ts = (item['timestamp'] as num?)?.toInt();
    final o = (item['open'] as num?)?.toDouble();
    final h = (item['high'] as num?)?.toDouble();
    final l = (item['low'] as num?)?.toDouble();
    final c = (item['close'] as num?)?.toDouble();
    if (ts == null || ts < minTime || ts > maxTime || o == null || h == null || l == null || c == null) {
      throw const MarketDataException('شمعة خارج الفترة المطلوبة أو بها حقول ناقصة.');
    }
    return MarketBar(ts, TradeCandle(o, h, l, c));
  }).toList(growable: false);
  validateBars(bars);
  return bars;
}

void validateBars(List<MarketBar> bars) {
  var lastTime = -1;
  for (final bar in bars) {
    final c = bar.candle;
    if (bar.timestamp <= lastTime || !c.open.isFinite || !c.high.isFinite ||
        !c.low.isFinite || !c.close.isFinite || c.low <= 0 ||
        c.low > c.high || c.open < c.low || c.close < c.low ||
        c.open > c.high || c.close > c.high) {
      throw const MarketDataException('ترتيب الشموع أو قيم OHLC غير صحيحة.');
    }
    lastTime = bar.timestamp;
  }
}
