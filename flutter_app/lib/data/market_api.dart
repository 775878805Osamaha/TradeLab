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
  /// Includes the token which actually authorized this HTTP request. A slow
  /// response from an older login must not replace the current session.
  void Function(String requestToken, String refreshedToken)? onSessionRefresh;
  // One broker symbol-list request per authorized account, including when
  // quote requests for several forex instruments arrive concurrently.
  final Map<String, Future<Map<String, int>>> _symbolLists = {};

  void forgetCTraderSymbols() => _symbolLists.clear();

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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw const MarketDataException('انتهت جلسة cTrader. أعد ربط الحساب.', sessionExpired: true);
      }
      throw MarketDataException('فشل الاتصال بالمصدر (${response.statusCode}). أعد المحاولة.');
    }
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      final refreshed = response.headers['x-tradelab-session'];
      if (token != null && refreshed != null && refreshed.isNotEmpty) {
        onSessionRefresh?.call(token, refreshed);
      }
      return data;
    } catch (_) {
      throw const MarketDataException('أعاد مصدر السوق استجابة غير صالحة.');
    }
  }

  Uri _gateway(String path, Map<String, String> query) =>
      Uri.parse(gateway).replace(path: path, queryParameters: query.isEmpty ? null : query);

  Future<bool> supportsFlutterOAuth() async {
    try {
      final status = await _json(_gateway('/healthz', {}));
      return status['flutterOAuthSupported'] == true && status['authEnabled'] == true;
    } catch (_) {return false;}
  }

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
    final pending = _symbolLists.putIfAbsent(accountId,
        () => _fetchSymbolList(token: token, accountId: accountId));
    try {
      final id = (await pending)[symbol.toUpperCase()];
      if (id != null) return id;
    } catch (_) {
      // A rejected request must be retryable on the next deliberate refresh.
      if (identical(_symbolLists[accountId], pending)) _symbolLists.remove(accountId);
      rethrow;
    }
    throw MarketDataException('رمز $symbol غير متاح لدى وسيط حساب cTrader المحدد.');
  }

  Future<Map<String, int>> _fetchSymbolList({required String token,
    required String accountId}) async {
    final data = await _json(_gateway('/v1/symbols', {'accountId': accountId}), token: token);
    final entries = data['symbols'];
    if (entries is! List) throw const MarketDataException('قائمة رموز cTrader غير صالحة.');
    final ids = <String, int>{};
    for (final item in entries) {
      if (item is! Map || item['archived'] == true) continue;
      final name = (item['symbolName'] ?? item['name'])?.toString().toUpperCase().replaceAll('/', '');
      final id = int.tryParse('${item['symbolId']}');
      if (name != null && id != null && id > 0) ids[name] = id;
    }
    return ids;
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
    final verified = parseVerifiedBars(data['candles'],
      sourceType: TradeSource.ctrader, minTime: start, maxTime: end);
    // cTrader trendbars are timestamped at their OPEN. An in-progress bar can
    // still change its high, low and close. Only closed bars may enter Replay,
    // the immutable SQLite archive or paper-trade research.
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final closedThrough = end < now ? end : now;
    return verified.where((bar) =>
      _barEndMs(bar.timestamp, timeframe) <= closedThrough,
    ).toList(growable: false);
  }

  /// Returns a complete, chronologically ordered six-day BID tick window.
  /// cTrader may truncate a page (hasMore=true) at its per-request limit.
  /// Split its time interval into disjoint inclusive halves instead of
  /// paging from oldestTimestamp - 1 (which loses same-ms broker ticks).
  /// Existing six-day chart window, or a specific validated subrange when
  /// refreshing only the time elapsed after the last verified SQLite window.
  Future<List<MarketTick>> ctraderBidTicks({
    required String token,
    required String accountId,
    required String symbol,
    required DateTime before,
  }) {
    final endMs = before.toUtc().millisecondsSinceEpoch;
    return ctraderBidTicksRange(
      token: token,
      accountId: accountId,
      symbol: symbol,
      fromMs: endMs - const Duration(days: 6).inMilliseconds,
      toMs: endMs,
    );
  }

  /// Fetch only the missing inclusive milliseconds from cTrader.
  /// Never infer ticks from candles or accept truncated responses.
  Future<List<MarketTick>> ctraderBidTicksRange({
    required String token,
    required String accountId,
    required String symbol,
    required int fromMs,
    required int toMs,
  }) async {
    if (fromMs < 0 || toMs < fromMs ||
        toMs - fromMs > const Duration(days: 6).inMilliseconds) {
      throw const MarketDataException(
          'النطاق الزمني المطلوب لتيكات cTrader غير صالح.');
    }
    final id = await symbolId(
      token: token, accountId: accountId, symbol: symbol);
    const maxTicks = 1000000;
    const maxRequests = 4096;
    const maxPageTicks = 100000;
    var requests = 0;
    final results = <MarketTick>[];

    Future<void> loadInterval(int fromMs, int toMs) async {
      requests++;
      if (requests > maxRequests) {
        throw const MarketDataException(
            'تجاوز تاريخ cTrader عدد الطلبات الآمن؛ جرّب فترة أقصر.');
      }
      final data = await _json(_gateway('/v1/ticks', {
        'accountId': accountId, 'symbolId': '$id',
        'from': '$fromMs', 'to': '$toMs',
      }), token: token);
      if (data['source'] != 'ctrader' ||
          data['quoteType'] != 'bid' ||
          '${data['symbolId']}' != '$id' ||
          data['hasMore'] is! bool) {
        throw const MarketDataException(
            'تعذر التحقق من مصدر تيكات BID أو حالة اكتمالها.');
      }

      if (data['hasMore'] == true) {
        if (fromMs == toMs) {
          // The provider cannot disambiguate more ticks within a single
          // millisecond. No fabricated ordering or partial Range candles.
          throw const MarketDataException(
              'cTrader أعاد تيكات غير مكتملة داخل مللي ثانية واحدة.');
        }
        final middle = fromMs + (toMs - fromMs) ~/ 2;
        await loadInterval(fromMs, middle);
        await loadInterval(middle + 1, toMs);
        return;
      }

      final rows = data['ticks'];
      if (rows is! List || rows.length > maxPageTicks ||
          results.length + rows.length > maxTicks) {
        throw const MarketDataException(
            'تجاوزت تيكات cTrader الحد الآمن للذاكرة أو حجم الصفحة.');
      }
      var previous = fromMs;
      for (final entry in rows) {
        if (entry is! Map) {
          throw const MarketDataException('تيكات cTrader غير صالحة.');
        }
        final time = (entry['timestamp'] as num?)?.toInt();
        final price = (entry['price'] as num?)?.toDouble();
        if (time == null || time < fromMs || time > toMs ||
            time < previous || price == null ||
            !price.isFinite || price <= 0) {
          throw const MarketDataException(
              'ترتيب تيكات cTrader أو أسعارها غير صالح.');
        }
        results.add(MarketTick(time, price));
        previous = time;
      }
    }

    // Left-to-right recursive loading preserves event order and all
    // same-millisecond ticks; never deduplicate genuine broker events.
    await loadInterval(fromMs, toMs);
    return results;
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

  Future<MarketQuote> ctraderQuote({required String token, required String accountId,
    required String symbol}) async {
    final id = await symbolId(token: token, accountId: accountId, symbol: symbol);
    final data = await _json(_gateway('/v1/spot', {
      'accountId': accountId, 'symbolId': '$id',
    }), token: token);
    final bid = (data['bid'] as num?)?.toDouble();
    final ask = (data['ask'] as num?)?.toDouble();
    final timestamp = (data['timestamp'] as num?)?.toInt();
    if (data['source'] != 'ctrader' || '${data['symbolId']}' != '$id' ||
        timestamp == null || timestamp <= 0 || bid == null || ask == null ||
        !bid.isFinite || !ask.isFinite || bid <= 0 || ask < bid) {
      throw const MarketDataException('تعذر التحقق من السعر المباشر لـcTrader.');
    }
    return MarketQuote(symbol: symbol, source: TradeSource.ctrader,
      bid: bid, ask: ask, timestampMs: timestamp);
  }

  Future<double> ctraderBid({required String token, required String accountId,
    required String symbol}) async => (await ctraderQuote(
      token: token, accountId: accountId, symbol: symbol)).bid;

  /// Binance best bid/ask, not the last trade or an estimated spread.
  Future<MarketQuote> binanceQuote(String symbol) async {
    if (!const {'BTCUSDT', 'ETHUSDT'}.contains(symbol)) {
      throw const MarketDataException('رمز الكريبتو غير معتمد.');
    }
    final data = await _json(Uri.https('api.binance.com',
      '/api/v3/ticker/bookTicker', {'symbol': symbol}));
    final bid = double.tryParse('${data['bidPrice']}');
    final ask = double.tryParse('${data['askPrice']}');
    if (data['symbol'] != symbol || bid == null || ask == null ||
        !bid.isFinite || !ask.isFinite || bid <= 0 || ask < bid) {
      throw const MarketDataException('أسعار BID/ASK المستلمة من Binance غير صالحة.');
    }
    // bookTicker has no exchange event timestamp. Record receipt time,
    // never claim this is a broker-provided timestamp.
    return MarketQuote(symbol: symbol, source: TradeSource.binance,
      bid: bid, ask: ask, timestampMs: DateTime.now().toUtc().millisecondsSinceEpoch);
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

/// Exclusive close boundary for a broker candle, including calendar months.
/// Use UTC so daylight-saving transitions never shift daily/weekly candles.
int _barEndMs(int openMs, String timeframe) {
  if (timeframe == '1M') {
    final open = DateTime.fromMillisecondsSinceEpoch(openMs, isUtc: true);
    return DateTime.utc(open.year, open.month + 1).millisecondsSinceEpoch;
  }
  final minutes = switch (timeframe) {
    '1m' => 1, '3m' => 3, '5m' => 5, '15m' => 15,
    '30m' => 30, '1h' => 60, '4h' => 240,
    '1D' => 1440, '1W' => 10080,
    _ => throw const MarketDataException('إطار زمني غير مدعوم'),
  };
  return openMs + minutes * 60000;
}

class MarketDataException implements Exception {
  const MarketDataException(this.message, {this.sessionExpired = false});
  final String message;
  final bool sessionExpired;
  @override
  String toString() => message;
}

class MarketQuote {
  const MarketQuote({required this.symbol, required this.source,
    required this.bid, required this.ask, required this.timestampMs});

  final String symbol;
  final TradeSource source;
  final double bid;
  final double ask;
  final int timestampMs;

  /// A simulated BUY crosses the ask; a simulated SELL crosses the bid.
  double executionPrice({required bool buy}) => buy ? ask : bid;

  void assertFresh({required int nowMs, int maxAgeMs = 90000}) {
    final age = nowMs - timestampMs;
    if (timestampMs <= 0 || age < -5000 || age > maxAgeMs ||
        !bid.isFinite || !ask.isFinite || bid <= 0 || ask < bid) {
      throw const MarketDataException(
        'السعر قديم أو غير صالح. تعذر تنفيذ صفقة تجريبية حتى وصول سعر حديث.');
    }
  }
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
