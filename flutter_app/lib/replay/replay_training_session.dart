import '../data/tradelab_data.dart';

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
  }

  void prepend(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    if (count == 0) return;
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
    for (var bar = _visibleCount; bar < newVisibleCount; bar++) {
      final candle = candles[bar];
      for (var i = 0; i < _trades.length; i++) {
        final trade = _trades[i];
        // A trade entered at a candle's close is NOT exposed to its
        // earlier high/low: only subsequent revealed candles can fill exits.
        if (!trade.isOpen || trade.entryIndex >= bar) continue;
        final stopped = trade.stopLoss != null &&
            (trade.side == ReplaySide.buy
                ? candle.low <= trade.stopLoss!
                : candle.high >= trade.stopLoss!);
        final targeted = trade.takeProfit != null &&
            (trade.side == ReplaySide.buy
                ? candle.high >= trade.takeProfit!
                : candle.low <= trade.takeProfit!);
        if (stopped) {
          _trades[i] = trade.close(
              bar, trade.stopLoss!, ReplayExitReason.stopLoss);
        } else if (targeted) {
          _trades[i] = trade.close(
              bar, trade.takeProfit!, ReplayExitReason.takeProfit);
        }
      }
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
