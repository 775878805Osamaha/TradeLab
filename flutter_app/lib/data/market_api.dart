import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'tradelab_data.dart';
import 'ctrader_closed_bar_cutoff.dart';

/// Selective off-main-isolate decoding of dense broker tick payloads.
/// Small messages avoid isolate overhead; only verified cTrader BID pages
/// can be large enough to interrupt gesture and frame scheduling.
class MarketJsonDecodePolicy {
  const MarketJsonDecodePolicy._();
  static const minOffloadChars = 128 * 1024;

  static bool shouldOffload({required String path, required int chars}) =>
      path == '/v1/ticks' && chars >= minOffloadChars;
}

/// Accept broker milliseconds only when the source number is exact.
/// Truncating 1700000000000.75 via toInt() would silently move an authentic
/// BID event or candle open into a different millisecond, corrupting Replay.
int? _exactBrokerMillisecond(Object? source) {
  if (source is! num || !source.isFinite || source < 0 ||
      source > 8640000000000000 || source % 1 != 0) {
    return null;
  }
  return source.toInt();
}

dynamic _convertDenseBidRow(dynamic entry) {
  if (entry is Map) {
    final time = _exactBrokerMillisecond(entry['timestamp']);
    final value = entry['price'];
    if (time != null && value is num) {
      return MarketTick(time, value.toDouble());
    }
  }
  // Retain malformed records for the caller's strict validation to reject.
  return entry;
}

Map<String, dynamic> _decodeBrokerObject(String payload) {
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, dynamic>) throw const FormatException();
  return decoded;
}

/// Dense broker BID history is decoded AND converted to MarketTick on the
/// worker isolate. The source/quote/account identity, order and exact range
/// are still validated by the requesting page before a single tick is used.
/// Preserve malformed records for the existing validation to reject; never
/// silently omit a broker event or fabricate a replacement.
Map<String, dynamic> _decodeDenseBrokerBidTicks(String payload) {
  final decoded = _decodeBrokerObject(payload);
  final rows = decoded['ticks'];
  if (rows is List && rows.length <= 100000) {
    decoded['ticks'] = <dynamic>[
      for (final entry in rows) _convertDenseBidRow(entry),
    ];
  }
  return decoded;
}

/// Fail closed on source-integrity and broker-permission errors. They
/// cannot be repaired by retrying the identical BID request, and silently
/// retrying them would hide a real broker rejection from the user.
bool _terminalBidGatewayFailure(String body) {
  if (body.length > 4096) return false;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return false;
    // The cTrader gateway signs REQUEST_FREQUENCY_EXCEEDED as a
    // broker rejection, but the broker's history-rate limit is transient.
    // Retry only that documented code, not incorrect boundaries, missing
    // permission or malformed/unusable tick data.
    if (decoded['error'] == 'ctrader_broker_rejected_request') {
      return decoded['brokerCode'] != 'REQUEST_FREQUENCY_EXCEEDED';
    }
    return const {
      'ctrader_tick_history_unusable',
      'invalid_request',
    }.contains(decoded['error']);
  } catch (_) {
    return false;
  }
}

bool _rateLimitedBidGatewayFailure(String body) {
  if (body.length > 4096) return false;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> &&
        decoded['error'] == 'ctrader_broker_rejected_request' &&
        decoded['brokerCode'] == 'REQUEST_FREQUENCY_EXCEEDED';
  } catch (_) {
    return false;
  }
}

/// The only permitted providers: cTrader for forex/gold, Binance for crypto.
/// No demo, fallback feed, or OHLC-derived ticks are permitted here.
class MarketApi {
  MarketApi({http.Client? client, this.gateway = 'https://tradelab-vercel-gateway.vercel.app',
    this.onSessionRefresh}) : _client = client ?? http.Client();

  final http.Client _client;
  final String gateway;
  // (refreshedToken, tokenThatAuthorizedTheRequest). Prevent a late response
  // from one authorization from replacing credentials for another account.
  // Bound by MarketController even when tests or another app entrypoint
  // inject a custom HTTP client through MarketApi. The session controller
  // remains the only authority to accept a refreshed OAuth credential.
  void Function(String, String)? onSessionRefresh;
  // One broker symbol-list request per authorized account, including when
  // quote requests for several forex instruments arrive concurrently.
  final Map<String, Future<Map<String, int>>> _symbolLists = {};

  void forgetCTraderSymbols() => _symbolLists.clear();

  void close() => _client.close();

  Future<Map<String, dynamic>> _json(Uri url, {String? token, Object? body}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (body != null) headers['Content-Type'] = 'application/json';
    // The cTrader gateway can transiently reject dense BID history with
    // 429/5xx (rate limit / cold-start / upstream unavailability). A single
    // unverified failed leaf used to discard the entire split Range request,
    // including successful sibling pages, and leave the chart empty.
    //
    // Retry the IDENTICAL inclusive BID interval at most twice with short
    // backoff; neither widen bounds nor make a partial page authoritative.
    // Do not retry auth, explicit broker rejection, invalid input or
    // inconsistent source data. Other routes retain their existing policy.
    late http.Response response;
    for (var attempt = 0; ; attempt++) {
      try {
        response = body == null
            ? await _client.get(url, headers: headers)
                .timeout(const Duration(seconds: 22))
            : await _client.post(url, headers: headers, body: jsonEncode(body))
                .timeout(const Duration(seconds: 22));
      } catch (_) {
        throw const MarketDataException(
            'تعذر الوصول إلى مصدر السوق. تحقق من الإنترنت وأعد المحاولة.');
      }
      if (url.path != '/v1/ticks' ||
          attempt >= 2 ||
          !const {429, 502, 503, 504}.contains(response.statusCode) ||
          _terminalBidGatewayFailure(response.body)) {
        break;
      }
      // The broker explicitly asks callers to slow down after exceeding
      // its historical-query rate. A longer bounded wait avoids hammering
      // the next connection while ordinary gateway 5xx keep short backoff.
      final backoffMs = _rateLimitedBidGatewayFailure(response.body)
          ? 750 * (attempt + 1)
          : 250 * (attempt + 1);
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw const MarketDataException('انتهت جلسة cTrader. أعد ربط الحساب.', sessionExpired: true);
      }
      // The backend returns bounded public reason codes only. Never
      // expose raw cTrader responses, private account identifiers or tokens.
      String? reason;
      String? brokerCode;
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['error'] is String) {
          reason = data['error'] as String;
          if (data['brokerCode'] is String) {
            brokerCode = data['brokerCode'] as String;
          }
        }
      } catch (_) {}
      if (url.path == '/v1/ticks') {
        if (reason == 'ctrader_tick_history_unusable') {
          throw const MarketDataException(
            'أعاد cTrader تيكات BID غير مكتملة أو غير متسقة. '
            'لم نعرض شموع مدى غير موثقة.');
        }
        if (reason == 'ctrader_broker_rejected_request') {
          if (brokerCode == 'REQUEST_FREQUENCY_EXCEEDED') {
            throw const MarketDataException(
              'تجاوزت طلبات تاريخ BID حد وسيط cTrader المؤقت. '
              'أعد المحاولة بعد قليل؛ لم نعرض بيانات غير مكتملة.');
          }
          throw const MarketDataException(
            'رفض وسيط cTrader طلب تاريخ تيكات BID. '
            'تحقق من دعم الوسيط للرمز XAUUSD وتاريخ التيكات.');
        }
        if (reason == 'ctrader_response_timeout') {
          throw const MarketDataException(
            'انتهت مهلة رد cTrader على طلب تيكات المدى. '
            'أعد المحاولة أو اختر حجم مدى أصغر.');
        }
        if (reason == 'ctrader_connection_failed' ||
            reason == 'ctrader_broker_unavailable') {
          throw const MarketDataException(
            'تعذر اتصال البوابة بخادم cTrader لجلب تيكات المدى. '
            'تحقق من الاتصال وأعد المحاولة.');
        }
      }
      if (url.path == '/v1/candles') {
        if (reason == 'ctrader_candle_history_unusable') {
          throw const MarketDataException(
              'وصلت شموع غير متسقة من cTrader. '
              'لم يتم عرض أسعار غير موثوقة؛ أعد تحميل الشارت.');
        }
        if (reason == 'ctrader_broker_rejected_request') {
          throw const MarketDataException(
              'رفض وسيط cTrader طلب تاريخ الشموع. '
              'تحقق من الحساب والرمز والإطار الزمني.');
        }
        if (reason == 'invalid_request') {
          throw const MarketDataException(
              'رفضت بوابة cTrader نطاق طلب الشموع. '
              'يلزم تحديث التطبيق أو إعادة اختيار الإطار.');
        }
      }
      throw MarketDataException(
          'فشل الاتصال بالمصدر (${response.statusCode}). أعد المحاولة.');
    }
    try {
      // Both JSON decoding and MarketTick allocations of dense BID pages
      // happen in the worker isolate; frame scheduling on the chart UI
      // only needs the lightweight final chronology/price verification.
      final Map<String, dynamic> data;
      if (MarketJsonDecodePolicy.shouldOffload(
          path: url.path, chars: response.body.length)) {
        data = await compute<String, Map<String, dynamic>>(
          _decodeDenseBrokerBidTicks, response.body,
          debugLabel: 'tradelab-ctrader-bid-json-and-ticks');
      } else {
        data = _decodeBrokerObject(response.body);
      }
      // A failed or malformed HTTP response may NEVER refresh a token.
      // The controller also confirms that the originating credential is
      // still active before accepting a signed header from the gateway.
      final refreshed = response.headers['x-tradelab-session'];
      if (token != null && refreshed != null && refreshed.isNotEmpty) {
        onSessionRefresh?.call(refreshed, token);
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

  /// cTrader Trendbars are broker OHLC, not Range candles or synthetic
  /// approximations. Fetch a bounded interval of at most 900 bar slots, so
  /// the broker's 1000-bar response cap cannot silently hide recent M1 data.
  ///
  /// Never show the still-forming candle as if its OHLC were finalized.
  static Duration ctraderCandleLookback(String timeframe) {
    final minutes = switch (timeframe) {
      '1m' => 1, '2m' => 2, '3m' => 3, '5m' => 5,
      '15m' => 15, '30m' => 30, '1h' => 60, '4h' => 240,
      '1D' => 1440, '1W' => 10080, '1M' => 43200,
      _ => throw const MarketDataException('إطار زمني غير مدعوم'),
    };
    final maxWindow = const Duration(days: 89).inMilliseconds;
    final capped = minutes * 60000 * 900;
    return Duration(milliseconds: capped < maxWindow ? capped : maxWindow);
  }

  Future<List<MarketBar>> ctraderCandles({
    required String token,
    required String accountId,
    required String symbol,
    required String timeframe,
    required DateTime before,
    int? fromTimestampMs,
  }) async {
    final period = switch (timeframe) {
      '1m' => 'M1', '2m' => 'M2', '3m' => 'M3',
      '5m' => 'M5', '15m' => 'M15', '30m' => 'M30',
      '1h' => 'H1', '4h' => 'H4',
      '1D' => 'D1', '1W' => 'W1', '1M' => 'MN1',
      _ => throw const MarketDataException('إطار زمني غير مدعوم'),
    };
    final id = await symbolId(token: token, accountId: accountId,
        symbol: symbol);
    final requestedEnd = before.toUtc().millisecondsSinceEpoch;
    final frame = ctraderCandleLookback(timeframe);
    // Intraday time frames have exact minute boundaries. Historical
    // Trendbars may include the active bar; exclude it from backtest/Replay.
    final frameMinutes = switch (timeframe) {
      '1m' => 1, '2m' => 2, '3m' => 3, '5m' => 5,
      '15m' => 15, '30m' => 30, '1h' => 60,
      '4h' => 240, _ => 0,
    };
    // Broker nominal day/week/month opens can precede UTC boundaries.
    // Apply a conservative calendar guard before broker paging so Replay
    // never assumes that midnight UTC proves the most recent bar has closed.
    final closedEnd = CTraderClosedBarCutoff.conservativeLatestAllowedOpenMs(
        timeframe, DateTime.now().toUtc());
    final endMs = requestedEnd < closedEnd ? requestedEnd : closedEnd;
    final startMs = fromTimestampMs ??
        endMs - frame.inMilliseconds;
    if (startMs < 0 || endMs < startMs ||
        endMs - startMs > frame.inMilliseconds) {
      throw const MarketDataException('فترة الشموع المطلوبة غير صالحة.');
    }
    final data = await _json(_gateway('/v1/candles', {
      'accountId': accountId, 'symbolId': '$id', 'period': period,
      'from': '$startMs', 'to': '$endMs', 'count': '900',
    }), token: token);
    if (data['source'] != 'ctrader' || data['period'] != period ||
        '${data['symbolId']}' != '$id' ||
        '${data['accountId']}' != accountId) {
      throw const MarketDataException('لم يتم التحقق من مصدر شموع cTrader.');
    }
    if (data['hasMore'] is! bool) {
      throw const MarketDataException(
          'لم يتم التحقق من حالة صفحات شموع cTrader.');
    }
    // cTrader may reject the requested time span and accept the documented
    // count-back form (count + toTimestamp without fromTimestamp). Genuine
    // weekend/holiday candles can then precede our requested lower bound.
    // The gateway explicitly marks that fallback; all broker provenance,
    // strict chronological order and the upper time limit still apply.
    if (data['queryMode'] != null && data['queryMode'] != 'count_back') {
      throw const MarketDataException('صيغة صفحة شموع cTrader غير معروفة.');
    }
    final bars = parseVerifiedBars(data['candles'],
        sourceType: TradeSource.ctrader,
        minTime: data['queryMode'] == 'count_back' ? 0 : startMs,
        maxTime: endMs);
    // cTrader can return an authenticated newest-first PAGE when the broker
    // rejects a wide window or reaches its count limit. The chart already
    // loads older history using an exclusive cursor (earliest bar - 1ms).
    // Keep these genuine verified candles visible without claiming the whole
    // requested interval is complete. Never accept an empty truncated page:
    // it has no cursor with which the chart could recover older history.
    if (data['hasMore'] == true && bars.isEmpty) {
      throw const MarketDataException(
          'صفحة cTrader غير مكتملة ولا تحتوي شموعًا للتحقق منها.');
    }
    if (frameMinutes > 0) {
      final stepMs = frameMinutes * 60000;
      for (final bar in bars) {
        if (bar.timestamp % stepMs != 0) {
          throw const MarketDataException(
              'توقيت شموع cTrader لا يتوافق مع الإطار المختار.');
        }
      }
    }
    return bars;
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

    // Work-stealing two-lane interval queue. The previous algorithm only
    // split the root in parallel; each half then ran depth-first in a single
    // lane. When one half ended early, its lane stayed idle while the other
    // had dozens of remaining truncated cTrader pages. Both lanes now draw
    // from the SAME bounded queue until all authenticated intervals finish.
    //
    // A pending entry represents a *real inclusive broker interval*, never
    // inferred market activity or a synthetic BID tick. Intervals split at
    // exact millisecond boundaries; each original event is kept, even if
    // multiple BID updates have identical timestamps.
    final waiting = Queue<({int fromMs, int toMs})>()
      ..add((fromMs: fromMs, toMs: toMs));
    final pages = <int, List<MarketTick>>{};
    var pending = 1; // Queued and currently in-flight source intervals.
    var requests = 0;
    var loadedTicks = 0;
    Completer<void>? wakeup;
    Object? failure;
    StackTrace? failureTrace;

    void notifyWaitingWorkers() {
      final waitingWorker = wakeup;
      wakeup = null;
      waitingWorker?.complete();
    }

    Future<void> downloadWorker() async {
      while (failure == null) {
        if (waiting.isEmpty) {
          if (pending == 0) return;
          // Another lane is waiting on the broker and may enqueue children.
          // Do not exit while authenticated history remains unfinished.
          await (wakeup ??= Completer<void>()).future;
          continue;
        }
        final window = waiting.removeFirst();
        final pageFrom = window.fromMs;
        final pageTo = window.toMs;
        try {
          requests++;
          if (requests > maxRequests) {
            throw const MarketDataException(
                'تجاوز تاريخ cTrader عدد الطلبات الآمن؛ جرّب فترة أقصر.');
          }
          final data = await _json(_gateway('/v1/ticks', {
            'accountId': accountId, 'symbolId': '$id',
            'from': '$pageFrom', 'to': '$pageTo',
          }), token: token);
          if (data['source'] != 'ctrader' ||
              data['quoteType'] != 'bid' ||
              '${data['symbolId']}' != '$id' ||
              // Some gateway versions omit accountId in the signed response.
              // If the broker does supply it, refuse to splice another
              // authorized account's BID history into the current chart.
              (data['accountId'] != null &&
                  '${data['accountId']}' != accountId) ||
              data['hasMore'] is! bool) {
            throw const MarketDataException(
                'تعذر التحقق من مصدر تيكات BID أو حالة اكتمالها.');
          }
          if (data['hasMore'] == true) {
            if (pageFrom == pageTo) {
              // Splitting below one millisecond would drop real same-ms
              // events. Never label an incomplete page as verified.
              throw const MarketDataException(
                  'cTrader أعاد تيكات غير مكتملة داخل مللي ثانية واحدة.');
            }
            final middle = pageFrom + (pageTo - pageFrom) ~/ 2;
            pending += 2;
            waiting.add((fromMs: pageFrom, toMs: middle));
            waiting.add((fromMs: middle + 1, toMs: pageTo));
            continue;
          }

          final rows = data['ticks'];
          if (rows is! List || rows.length > maxPageTicks ||
              loadedTicks + rows.length > maxTicks) {
            throw const MarketDataException(
                'تجاوزت تيكات cTrader الحد الآمن للذاكرة أو حجم الصفحة.');
          }
          final page = <MarketTick>[];
          var previous = pageFrom;
          for (final entry in rows) {
            final int? time;
            final double? price;
            if (entry is MarketTick) {
              time = entry.timestamp;
              price = entry.bid;
            } else if (entry is Map) {
              time = _exactBrokerMillisecond(entry['timestamp']);
              final rawPrice = entry['price'];
              price = rawPrice is num ? rawPrice.toDouble() : null;
            } else {
              throw const MarketDataException('تيكات cTrader غير صالحة.');
            }
            if (time == null || time < pageFrom || time > pageTo ||
                time < previous || price == null ||
                !price.isFinite || price <= 0) {
              throw const MarketDataException(
                  'ترتيب تيكات cTrader أو أسعارها غير صالح.');
            }
            page.add(entry is MarketTick ? entry : MarketTick(time, price));
            previous = time;
          }
          loadedTicks += page.length;
          pages[pageFrom] = page;
        } catch (error, stack) {
          // Never return a partially downloaded archive after *any* failed
          // leaf, malformed source, memory cap or request-budget error.
          // An already running second request may finish, but cannot publish.
          failure ??= error;
          failureTrace ??= stack;
        } finally {
          pending--;
          notifyWaitingWorkers();
        }
      }
    }

    await Future.wait<void>([downloadWorker(), downloadWorker()]);
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureTrace!);
    }
    // Stable chronological reassembly by VERIFIED, disjoint source bounds.
    // Never reorder same-millisecond events inside a downloaded leaf.
    final starts = pages.keys.toList()..sort();
    final result = <MarketTick>[];
    for (final firstMs in starts) {
      result.addAll(pages[firstMs]!);
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

  Future<MarketQuote> ctraderQuote({required String token, required String accountId,
    required String symbol}) async {
    final id = await symbolId(token: token, accountId: accountId, symbol: symbol);
    final data = await _json(_gateway('/v1/spot', {
      'accountId': accountId, 'symbolId': '$id',
    }), token: token);
    final bid = (data['bid'] as num?)?.toDouble();
    final ask = (data['ask'] as num?)?.toDouble();
    final timestamp = _exactBrokerMillisecond(data['timestamp']);
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
      '30m' => '30m', '1h' => '1h', '2h' => '2h', '4h' => '4h', '1D' => '1d',
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
        final ts = _exactBrokerMillisecond(row[0]);
        final closeAt = _exactBrokerMillisecond(row[6]);
        // Malformed times cannot silently move a Binance candle across
        // Replay's cutoff, or turn an open candle into a completed one.
        if (ts == null || closeAt == null || closeAt <= ts) {
          throw const FormatException('Invalid Binance kline timestamps');
        }
        // Exclude the current, unclosed candle to keep Replay look-ahead-free.
        if (closeAt >= end) return null;
        final volume = row[5] == null ? null : double.tryParse('${row[5]}');
        if (row[5] != null && volume == null) throw const FormatException('Invalid volume');
        return MarketBar(ts, TradeCandle(double.parse('${row[1]}'), double.parse('${row[2]}'),
          double.parse('${row[3]}'), double.parse('${row[4]}'),
          timestampMs: ts, volume: volume));
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

/// Known volumes must not conflict at a verified overlapping timestamp.
/// Legacy records with missing volume are not evidence of zero volume.
bool conflictingKnownVolume(TradeCandle a, TradeCandle b) =>
    a.volume != null && b.volume != null && a.volume != b.volume;

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
    final ts = _exactBrokerMillisecond(item['timestamp']);
    final o = (item['open'] as num?)?.toDouble();
    final h = (item['high'] as num?)?.toDouble();
    final l = (item['low'] as num?)?.toDouble();
    final c = (item['close'] as num?)?.toDouble();
    if (ts == null || ts < minTime || ts > maxTime || o == null || h == null || l == null || c == null) {
      throw const MarketDataException('شمعة خارج الفترة المطلوبة أو بها حقول ناقصة.');
    }
    final rawVolume = item['volume'];
    if (rawVolume != null && rawVolume is! num) {
      throw const MarketDataException('حجم شمعة المصدر غير صالح.');
    }
    final volume = (rawVolume as num?)?.toDouble();
    return MarketBar(ts, TradeCandle(o, h, l, c, timestampMs: ts, volume: volume));
  }).toList(growable: false);
  validateBars(bars);
  return bars;
}

void validateBars(List<MarketBar> bars) {
  var lastTime = -1;
  for (final bar in bars) {
    final c = bar.candle;
    if (bar.timestamp <= lastTime ||
        (c.timestampMs != null && c.timestampMs != bar.timestamp) ||
        (c.volume != null && (!c.volume!.isFinite || c.volume! < 0)) ||
        !c.open.isFinite || !c.high.isFinite ||
        !c.low.isFinite || !c.close.isFinite || c.low <= 0 ||
        c.low > c.high || c.open < c.low || c.close < c.low ||
        c.open > c.high || c.close > c.high) {
      throw const MarketDataException('ترتيب الشموع أو قيم OHLC غير صحيحة.');
    }
    lastTime = bar.timestamp;
  }
}
