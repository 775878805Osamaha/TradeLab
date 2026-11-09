import '../data/market_api.dart';
import '../data/market_controller.dart';
import '../data/tradelab_data.dart';
import 'paper_journal_controller.dart';
import 'paper_ledger.dart';
import 'paper_risk_engine.dart';

abstract interface class PaperQuoteProvider {
  Future<MarketQuote> fetch(TradeSymbol symbol);
}

class LivePaperQuoteProvider implements PaperQuoteProvider {
  const LivePaperQuoteProvider(this.market);
  final MarketController market;

  @override
  Future<MarketQuote> fetch(TradeSymbol symbol) => market.paperQuote(symbol);
}

class PreparedPaperQuote {
  const PreparedPaperQuote(this.quote, this.accountKey, this.receivedAtMs);
  final MarketQuote quote;
  final String accountKey;
  final int receivedAtMs;
}

/// Executes locally only, at verified current bid/ask (not a broker fill).
/// There is no leverage, margin simulation, slippage or broker commission.
class PaperTradeService {
  PaperTradeService({required this.quotes, required this.journal,
    int Function()? nowMs}) : _nowMs = nowMs ?? _clock;

  final PaperQuoteProvider quotes;
  final PaperJournalController journal;
  final int Function() _nowMs;
  bool _openingRiskManaged = false;
  final PaperRiskEngine _risk = const PaperRiskEngine();

  static int _clock() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<PreparedPaperQuote> prepare(TradeSymbol symbol) async {
    if (!LedgerEntry.usdQuotedSymbols.contains(symbol.code)) {
      throw const FormatException('التداول التجريبي الحالي يدعم الرموز المسعّرة بالدولار فقط.');
    }
    final scope = journal.accountKey;
    final quote = await quotes.fetch(symbol);
    final now = _nowMs();
    if (scope != journal.accountKey || quote.symbol != symbol.code ||
        quote.source != symbol.source) {
      throw const MarketDataException('تغيّر الحساب أو اختلف مصدر السعر أثناء الطلب.');
    }
    quote.assertFresh(nowMs: now);
    return PreparedPaperQuote(quote, scope, now);
  }

  void _verify(PreparedPaperQuote prepared, TradeSymbol symbol) {
    final now = _nowMs();
    if (prepared.accountKey != journal.accountKey ||
        prepared.quote.symbol != symbol.code ||
        prepared.quote.source != symbol.source ||
        now < prepared.receivedAtMs ||
        now - prepared.receivedAtMs > 60000) {
      throw StateError('انتهى عرض السعر أو تغيّر الحساب. اطلب سعرًا جديدًا.');
    }
    prepared.quote.assertFresh(nowMs: now);
  }

  Future<void> open({required TradeSymbol symbol, required PaperSide side,
      required double units, required PreparedPaperQuote prepared}) async {
    _verify(prepared, symbol);
    final buy = side == PaperSide.buy;
    final timestamp = _nowMs();
    final record = LedgerEntry(
      id: 0, accountKey: prepared.accountKey, kind: LedgerKind.openTrade,
      timestampMs: timestamp, openedAtMs: timestamp,
      symbol: symbol.code, side: side, quantity: units,
      entryPrice: prepared.quote.executionPrice(buy: buy),
      fee: 0,
    );
    record.validate();
    await journal.add(record);
  }

  /// Only reads the current account's local ledger; no broker execution.
  PaperRiskAssessment assessRisk({required TradeSymbol symbol,
      required PaperSide side, required double stopLoss,
      required double takeProfit, required PaperRiskLimits limits,
      required PreparedPaperQuote prepared, double? units}) {
    _verify(prepared, symbol);
    return _risk.assess(
      plan: PaperTradePlan(side: side,
        entryPrice: prepared.quote.executionPrice(buy: side == PaperSide.buy),
        stopLoss: stopLoss, takeProfit: takeProfit),
      limits: limits, entries: journal.entries,
      nowMs: _nowMs(), requestedUnits: units);
  }

  /// Re-checks *after* confirmation, at the exact saved quote, before writing.
  /// The protective levels are stored as plans, not exchange stop orders.
  Future<void> openRiskManaged({required TradeSymbol symbol,
      required PaperSide side, required double units,
      required double stopLoss, required double takeProfit,
      required PaperRiskLimits limits,
      required PreparedPaperQuote prepared}) async {
    if (_openingRiskManaged) {
      throw StateError('هناك صفقة قيد التسجيل. انتظر اكتمالها.');
    }
    _openingRiskManaged = true;
    try {
      _verify(prepared, symbol);
      final timestamp = _nowMs();
      final record = LedgerEntry(
        id: 0, accountKey: prepared.accountKey, kind: LedgerKind.openTrade,
        timestampMs: timestamp, openedAtMs: timestamp,
        symbol: symbol.code, side: side, quantity: units,
        entryPrice: prepared.quote.executionPrice(buy: side == PaperSide.buy),
        stopLoss: stopLoss, takeProfit: takeProfit, fee: 0,
      );
      record.validate();
      await journal.addWithValidation(record, (currentEntries) {
        // Check the account, quote and funds inside the journal's write lock.
        _verify(prepared, symbol);
        final assessment = _risk.assess(
          plan: PaperTradePlan(side: side, entryPrice: record.entryPrice!,
            stopLoss: stopLoss, takeProfit: takeProfit),
          limits: limits, entries: currentEntries,
          nowMs: _nowMs(), requestedUnits: units);
        if (!assessment.allowed) {
          throw StateError(assessment.reasons.join(' '));
        }
      });
    } finally {
      _openingRiskManaged = false;
    }
  }

  Future<void> close({required LedgerEntry position,
      required PreparedPaperQuote prepared}) async {
    final symbol = tradeSymbols.firstWhere((item) => item.code == position.symbol,
      orElse: () => throw const FormatException('رمز الصفقة غير معتمد.'));
    _verify(prepared, symbol);
    if (position.kind != LedgerKind.openTrade) {
      throw StateError('تم إغلاق الصفقة بالفعل.');
    }
    // To close a BUY, SELL at bid; to close a SELL, BUY at ask.
    final exit = prepared.quote.executionPrice(buy: position.side == PaperSide.sell);
    await journal.closeTrade(position, exitPrice: exit,
      timestampMs: _nowMs());
  }
}
