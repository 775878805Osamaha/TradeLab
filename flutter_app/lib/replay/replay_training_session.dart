import '../data/tradelab_data.dart';
import 'replay_revealed_exit_index.dart';

/// Replay practice is entirely local and never submits an order to a broker
/// or the live/paper trading journal. P&L is PRICE DELTA x quantity, not USD.
enum ReplaySide { buy, sell }
enum ReplayExitReason { manual, stopLoss, takeProfit }

class ReplayTrainingTrade {
  const ReplayTrainingTrade({
    required this.id,
    required this.side,
    required this.entryIndex,
    required this.entryPrice,
    required this.quantity,
    this.stopLoss,
    this.takeProfit,
    this.exitIndex,
    this.exitPrice,
    this.exitReason,
  });

  final int id;
  final ReplaySide side;
  final int entryIndex;
  final double entryPrice;
  final double quantity;
  final double? stopLoss;
  final double? takeProfit;
  final int? exitIndex;
  final double? exitPrice;
  final ReplayExitReason? exitReason;

  bool get isOpen => exitIndex == null;

  double get realizedPricePnl => exitPrice == null
      ? 0
      : (exitPrice! - entryPrice) *
          (side == ReplaySide.buy ? 1 : -1) * quantity;

  ReplayTrainingTrade close(
      int index, double price, ReplayExitReason reason) =>
      ReplayTrainingTrade(
        id: id,
        side: side,
        entryIndex: entryIndex,
        entryPrice: entryPrice,
        quantity: quantity,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        exitIndex: index,
        exitPrice: price,
        exitReason: reason,
      );

  ReplayTrainingTrade reopen() => ReplayTrainingTrade(
        id: id,
        side: side,
        entryIndex: entryIndex,
        entryPrice: entryPrice,
        quantity: quantity,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
      );

  ReplayTrainingTrade shifted(int amount) => ReplayTrainingTrade(
        id: id,
        side: side,
        entryIndex: entryIndex + amount,
        entryPrice: entryPrice,
        quantity: quantity,
        stopLoss: stopLoss,
        takeProfit: takeProfit,
        exitIndex: exitIndex == null ? null : exitIndex! + amount,
        exitPrice: exitPrice,
        exitReason: exitReason,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'side': side.name,
        'entryIndex': entryIndex,
        'entryPrice': entryPrice,
        'quantity': quantity,
        'stopLoss': stopLoss,
        'takeProfit': takeProfit,
        'exitIndex': exitIndex,
        'exitPrice': exitPrice,
        'exitReason': exitReason?.name,
        'realizedPricePnl': realizedPricePnl,
      };
}

/// Deterministic trade simulation. It can only advance through revealed bars.
/// If the user rewinds, entries and exits from unrevealed bars are rolled back.
/// Intrabar SL+TP ambiguity is always resolved conservatively (SL first).
class ReplayTrainingSession {
  final List<ReplayTrainingTrade> _trades = [];
  int _visibleCount = 0;
  int _nextId = 1;
  ReplayRevealedExitIndex? _exitIndex;

  // For a handful of practice trades or normal one-bar playback, the
  // existing sequential loop avoids an unnecessary tree allocation.
  // A deep seek with MANY bracketed trades would otherwise perform
  // thousands of source-bar reads per trade on Flutter's UI isolate.
  static bool shouldUseIndexedExitSearch({
    required int newlyRevealedBars,
    required int watchedTrades,
  }) => newlyRevealedBars >= 2048 && watchedTrades >= 8 &&
      newlyRevealedBars * watchedTrades >= 100000;

  /// One authoritative fill policy shared by small-step playback and the
  /// indexed long-seek path. The trade never fills on its own entry bar;
  /// stop wins an unresolved intrabar SL+TP tie; inter-bar gaps fill at the
  /// actual following open (both adverse SL and favorable TP), before any
  /// simulated intrabar stop/target checks.
  static ReplayTrainingTrade? _exitOnBar(
      ReplayTrainingTrade trade, TradeCandle candle, int bar) {
    if (trade.entryIndex >= bar) return null;
    final stopped = trade.stopLoss != null &&
        (trade.side == ReplaySide.buy
            ? candle.low <= trade.stopLoss!
            : candle.high >= trade.stopLoss!);
    final targeted = trade.takeProfit != null &&
        (trade.side == ReplaySide.buy
            ? candle.high >= trade.takeProfit!
            : candle.low <= trade.takeProfit!);
    // TradingView's default broker emulator fills a price-based order
    // at the NEXT bar's opening price when it crosses the order level
    // inside the inter-bar gap (not at the old limit/target price).
    // This also means a TP filled immediately at OPEN wins over a later
    // stop hit within that same candle. These are verified OHLC prices,
    // not inferred sub-bar ticks or future Replay data.
    final targetAtOpen = targeted && (trade.side == ReplaySide.buy
        ? candle.open >= trade.takeProfit!
        : candle.open <= trade.takeProfit!);
    if (targetAtOpen) {
      return trade.close(
          bar, candle.open, ReplayExitReason.takeProfit);
    }
    if (stopped) {
      final fill = trade.side == ReplaySide.buy
          ? (candle.open < trade.stopLoss! ? candle.open : trade.stopLoss!)
          : (candle.open > trade.stopLoss! ? candle.open : trade.stopLoss!);
      return trade.close(bar, fill, ReplayExitReason.stopLoss);
    }
    if (targeted) {
      return trade.close(
          bar, trade.takeProfit!, ReplayExitReason.takeProfit);
    }
    return null;
  }

  int get visibleCount => _visibleCount;
  List<ReplayTrainingTrade> get trades =>
      List<ReplayTrainingTrade>.unmodifiable(_trades);
  int get openTradeCount => _trades.where((trade) => trade.isOpen).length;
  double get realizedPricePnl => _trades.fold<double>(0.0,
      (result, trade) => result + trade.realizedPricePnl);

  void clear() {
    _trades.clear();
    _visibleCount = 0;
    _nextId = 1;
    _exitIndex = null;
  }

  void prepend(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    if (count == 0) return;
    // A prepended verified prefix changes source indices and identity.
    _exitIndex = null;
    for (var index = 0; index < _trades.length; index++) {
      _trades[index] = _trades[index].shifted(count);
    }
    _visibleCount += count;
  }

  void moveTo(List<TradeCandle> candles, int newVisibleCount) {
    if (newVisibleCount < 0 || newVisibleCount > candles.length) {
      throw RangeError.range(newVisibleCount, 0, candles.length);
    }
    if (newVisibleCount < _visibleCount) {
      // Previously revealed bars are now future history again; drop their
      // extrema even though every query is separately prefix-bounded.
      _exitIndex = null;
      _trades.removeWhere((trade) => trade.entryIndex >= newVisibleCount);
      for (var i = 0; i < _trades.length; i++) {
        final trade = _trades[i];
        if (trade.exitIndex != null &&
            trade.exitIndex! >= newVisibleCount) {
          _trades[i] = trade.reopen();
        }
      }
      _visibleCount = newVisibleCount;
      return;
    }
    // Seeking 100k historical bars must not revisit already closed trades,
    // or open practice trades with no automatic stop/target. Those cannot
    // change until the user explicitly closes them at a revealed candle.
    final watchedTrades = <int>[];
    for (var i = 0; i < _trades.length; i++) {
      final trade = _trades[i];
      if (trade.isOpen &&
          (trade.stopLoss != null || trade.takeProfit != null)) {
        watchedTrades.add(i);
      }
    }
    if (watchedTrades.isEmpty) {
      _visibleCount = newVisibleCount;
      return;
    }

    if (shouldUseIndexedExitSearch(
      newlyRevealedBars: newVisibleCount - _visibleCount,
      watchedTrades: watchedTrades.length,
    )) {
      // The index reads ONLY source candles already revealed by THIS move.
      // Source swaps, Range prepend and rewind invalidate the old tree;
      // it cannot accidentally use the later OHLC bars hidden by Replay.
      final prior = _exitIndex;
      final tree = prior != null && identical(prior.source, candles) &&
              prior.indexedThrough <= newVisibleCount
          ? prior
          : ReplayRevealedExitIndex(candles);
      tree.indexThrough(newVisibleCount);
      _exitIndex = tree;
      for (final slot in watchedTrades) {
        final trade = _trades[slot];
        final fromBar = trade.entryIndex + 1 > _visibleCount
            ? trade.entryIndex + 1 : _visibleCount;
        if (fromBar >= newVisibleCount) continue;
        final firstHit = tree.firstCrossing(
          fromInclusive: fromBar,
          throughExclusive: newVisibleCount,
          lowAtMost: trade.side == ReplaySide.buy
              ? trade.stopLoss : trade.takeProfit,
          highAtLeast: trade.side == ReplaySide.buy
              ? trade.takeProfit : trade.stopLoss,
        );
        if (firstHit == null) continue;
        final settled = _exitOnBar(trade, candles[firstHit], firstHit);
        if (settled != null) _trades[slot] = settled;
      }
      _visibleCount = newVisibleCount;
      return;
    }

    // Fast, allocation-free sequential processing for ordinary 1-bar Replay
    // playback and small groups of trades. Exact fill policy is shared
    // with indexed long seeks above.
    for (var bar = _visibleCount; bar < newVisibleCount; bar++) {
      final candle = candles[bar];
      for (var slot = watchedTrades.length - 1; slot >= 0; slot--) {
        final index = watchedTrades[slot];
        final settled = _exitOnBar(_trades[index], candle, bar);
        if (settled == null) continue;
        _trades[index] = settled;
        watchedTrades[slot] = watchedTrades.last;
        watchedTrades.removeLast();
      }
      if (watchedTrades.isEmpty) break;
    }
    _visibleCount = newVisibleCount;
  }

  ReplayTrainingTrade enter({
    required ReplaySide side,
    required List<TradeCandle> candles,
    required double quantity,
    double? stopLoss,
    double? takeProfit,
  }) {
    if (_visibleCount < 1 || _visibleCount > candles.length) {
      throw StateError('Replay has no revealed candle for an entry.');
    }
    final entry = candles[_visibleCount - 1].close;
    if (!entry.isFinite || entry <= 0 ||
        !quantity.isFinite || quantity <= 0 || quantity > 1000000) {
      throw ArgumentError('Invalid practice price or quantity.');
    }
    if (stopLoss != null && (!stopLoss.isFinite || stopLoss <= 0 ||
        (side == ReplaySide.buy ? stopLoss >= entry : stopLoss <= entry))) {
      throw ArgumentError('Stop must be on the loss side of entry.');
    }
    if (takeProfit != null && (!takeProfit.isFinite || takeProfit <= 0 ||
        (side == ReplaySide.buy ? takeProfit <= entry : takeProfit >= entry))) {
      throw ArgumentError('Target must be on the profit side of entry.');
    }
    final trade = ReplayTrainingTrade(
      id: _nextId++,
      side: side,
      entryIndex: _visibleCount - 1,
      entryPrice: entry,
      quantity: quantity,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
    );
    _trades.add(trade);
    return trade;
  }

  void closeAtCurrent(int tradeId, List<TradeCandle> candles) {
    if (_visibleCount < 1 || _visibleCount > candles.length) {
      throw StateError('No revealed market price.');
    }
    final index = _trades.indexWhere(
        (trade) => trade.id == tradeId && trade.isOpen);
    if (index < 0) throw StateError('Open practice trade not found.');
    final price = candles[_visibleCount - 1].close;
    if (!price.isFinite || price <= 0) {
      throw StateError('Invalid revealed market price.');
    }
    _trades[index] = _trades[index].close(
        _visibleCount - 1, price, ReplayExitReason.manual);
  }
}
