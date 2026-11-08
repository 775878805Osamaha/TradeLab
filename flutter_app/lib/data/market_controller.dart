import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'market_api.dart';
import 'tradelab_data.dart';

/// Owns authentication and explicit source states; never fabricates a quote.
class MarketController extends ChangeNotifier {
  MarketController({MarketApi? api, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    _api = api ?? MarketApi(onSessionRefresh: _onRefreshedToken);
  }

  late final MarketApi _api;
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'tradelab_flutter_ctrader_session';
  static const _pendingKey = 'tradelab_flutter_oauth_pending';
  String? _token;
  String? accountId;
  List<CTraderAccount> accounts = const [];
  final Map<String, double> cryptoPrices = {};
  final Map<String, double> forexPrices = {};
  bool busy = false;
  bool loadingQuotes = false;
  String? error;
  StreamSubscription<Uri>? _linksSubscription;

  bool get ctraderConnected => _token != null && accountId != null;
  bool get binanceConnected => cryptoPrices.isNotEmpty;

  Future<void> initialize({bool enableDeepLinks = true}) async {
    try {
      _token = await _storage.read(key: _tokenKey);
      if (_token != null) await _loadAccounts();
    } catch (_) {
      error = 'تعذر استعادة جلسة cTrader. أعد ربط الحساب إذا لزم.';
      notifyListeners();
    }
    if (enableDeepLinks) {
      try {
        final links = AppLinks();
        _linksSubscription = links.uriLinkStream.listen((uri) => completeOAuth(uri));
        final initial = await links.getInitialLink();
        if (initial != null) await completeOAuth(initial);
      } catch (_) {
        // Some widget test environments have no Android platform channels.
      }
    }
  }

  Future<void> connectCTrader() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!await _api.supportsFlutterOAuth()) {
        throw const MarketDataException(
          'بوابة cTrader لم تُحدّث بعد لدعم عودة تسجيل الدخول إلى Flutter. '
          'يجب نشر تحديث البوابة أولًا.');
      }
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final verifier = base64UrlEncode(bytes).replaceAll('=', '');
      final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      await _storage.write(key: _pendingKey,
          value: jsonEncode({'verifier': verifier,
            'created': DateTime.now().toUtc().millisecondsSinceEpoch}));
      final start = Uri.parse(_api.gateway).replace(path: '/auth/ctrader/start',
          queryParameters: {'challenge': challenge, 'client': 'flutter'});
      if (!await launchUrl(start, mode: LaunchMode.externalApplication)) {
        throw const MarketDataException('تعذر فتح متصفح تسجيل الدخول.');
      }
    } catch (e) {
      error = e is MarketDataException ? e.message : 'تعذر بدء تسجيل الدخول الآمن إلى cTrader.';
    } finally {busy = false; notifyListeners();}
  }

  Future<void> completeOAuth(Uri uri) async {
    if (uri.scheme != 'tradelabflutter' || uri.host != 'oauth' ||
        uri.path != '/ctrader' || !uri.hasQuery) return;
    final ticket = uri.queryParameters['ticket'];
    if (ticket == null || ticket.isEmpty) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final raw = await _storage.read(key: _pendingKey);
      if (raw == null) throw const MarketDataException('انتهت محاولة التفويض. ابدأ تسجيل الدخول من جديد.');
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      final age = DateTime.now().toUtc().millisecondsSinceEpoch - (pending['created'] as int);
      if (age < 0 || age > const Duration(minutes: 12).inMilliseconds ||
          pending['verifier'] is! String) {
        throw const MarketDataException('انتهت صلاحية التفويض. أعد ربط الحساب.');
      }
      final issued = await _api.redeem(ticket: ticket, verifier: pending['verifier'] as String);
      // Verify account access before activating a token or claiming connection.
      final authorized = await _api.accounts(issued);
      if (authorized.isEmpty) throw const MarketDataException('لا توجد حسابات cTrader مصرح بها.');
      _api.forgetCTraderSymbols();
      await _storage.write(key: _tokenKey, value: issued);
      _token = issued;
      accounts = authorized;
      accountId = authorized.first.id;
    } catch (e) {
      error = e is MarketDataException ? e.message : 'فشل تأكيد تسجيل الدخول. حاول مرة أخرى.';
    } finally {
      await _storage.delete(key: _pendingKey);
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadAccounts() async {
    final token = _token;
    if (token == null) return;
    try {
      accounts = await _api.accounts(token);
      accountId = accounts.isEmpty ? null : accounts.first.id;
      if (accounts.isEmpty) error = 'لا توجد حسابات cTrader متاحة لهذا التفويض.';
    } on MarketDataException catch (e) {
      if (e.sessionExpired) {
        await disconnect();
      } else {error = e.message;}
    } finally {notifyListeners();}
  }

  void chooseAccount(String id) {
    if (accounts.any((a) => a.id == id)) {
      accountId = id;
      _api.forgetCTraderSymbols();
      forexPrices.clear();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _token = null;
    accountId = null;
    accounts = const [];
    forexPrices.clear();
    _api.forgetCTraderSymbols();
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _pendingKey);
    notifyListeners();
  }

  void _onRefreshedToken(String newToken) {
    _token = newToken;
    unawaited(_storage.write(key: _tokenKey, value: newToken));
  }

  Future<List<MarketBar>> history(TradeSymbol symbol, String timeframe,
      {DateTime? before}) async {
    if (symbol.source == TradeSource.binance) {
      return _api.binanceCandles(symbol: symbol.code, timeframe: timeframe, before: before);
    }
    if (!ctraderConnected) throw const MarketDataException('اربط حساب cTrader لعرض أسعار الذهب والفوركس.');
    return _api.ctraderCandles(token: _token!, accountId: accountId!,
        symbol: symbol.code, timeframe: timeframe,
        before: before ?? DateTime.now().toUtc());
  }

  Future<List<MarketTick>> rangeTicks(TradeSymbol symbol, {DateTime? before}) async {
    if (symbol.source != TradeSource.ctrader || !ctraderConnected) {
      throw const MarketDataException('شموع المدى تتطلب تيكات BID حقيقية من cTrader.');
    }
    return _api.ctraderBidTicks(token: _token!, accountId: accountId!,
        symbol: symbol.code, before: before ?? DateTime.now().toUtc());
  }

  Future<double> pointSize(TradeSymbol symbol) async {
    if (!ctraderConnected || symbol.source != TradeSource.ctrader) {
      throw const MarketDataException('يلزم ربط cTrader لدقة تسعير شموع المدى.');
    }
    return _api.ctraderPointSize(token: _token!, accountId: accountId!, symbol: symbol.code);
  }

  /// Returns a fresh source quote on demand; never submits broker orders.
  Future<MarketQuote> paperQuote(TradeSymbol symbol) async {
    if (symbol.source == TradeSource.binance) {
      return _api.binanceQuote(symbol.code);
    }
    final account = accountId;
    final token = _token;
    if (!ctraderConnected || token == null || account == null) {
      throw const MarketDataException('اربط حساب cTrader للحصول على سعر فعلي للصفقة التجريبية.');
    }
    final quote = await _api.ctraderQuote(token: token,
      accountId: account, symbol: symbol.code);
    if (accountId != account || _token == null) {
      throw const MarketDataException('تغير حساب cTrader أثناء طلب السعر. أعد المحاولة.');
    }
    return quote;
  }

  Future<void> refreshQuotes() async {
    if (loadingQuotes) return;
    loadingQuotes = true;
    notifyListeners();
    final requestedAccount = accountId;
    await Future.wait(tradeSymbols.map((symbol) async {
      try {
        if (symbol.source == TradeSource.binance) {
          cryptoPrices[symbol.code] = await _api.binancePrice(symbol.code);
        } else if (ctraderConnected && requestedAccount != null) {
          final result = await _api.ctraderBid(
              token: _token!, accountId: requestedAccount, symbol: symbol.code);
          if (ctraderConnected && accountId == requestedAccount) {
            forexPrices[symbol.code] = result;
          }
        }
      } catch (_) {
        if (symbol.source == TradeSource.binance) {
          cryptoPrices.remove(symbol.code);
        } else {forexPrices.remove(symbol.code);}
      }
    }));
    loadingQuotes = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _linksSubscription?.cancel();
    _api.close();
    super.dispose();
  }
}
