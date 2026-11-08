import 'dart:math' as math;

/// A local, user-entered paper journal. No entry represents a broker order.
enum LedgerKind { deposit, withdrawal, openTrade, closedTrade }

enum PaperSide { buy, sell }

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.accountKey,
    required this.kind,
    required this.timestampMs,
    this.symbol,
    this.side,
    this.quantity,
    this.entryPrice,
    this.exitPrice,
    this.fee = 0,
    this.amount,
    this.openedAtMs,
  });

  final int id;
  final String accountKey;
  final LedgerKind kind;
  final int timestampMs;
  final String? symbol;
  final PaperSide? side;
  final double? quantity;
  final double? entryPrice;
  final double? exitPrice;
  final double fee;
  final double? amount;
  final int? openedAtMs;

  /// For this first journal, only USD-quoted symbols are eligible, and
  /// quantity means base-asset units (not FX lots or margin contracts).
  static const usdQuotedSymbols = <String>{
    'XAUUSD', 'EURUSD', 'GBPUSD', 'BTCUSDT', 'ETHUSDT',
  };

  double get realizedPnl {
    if (kind != LedgerKind.closedTrade) return 0;
    final direction = side == PaperSide.buy ? 1 : -1;
    return (exitPrice! - entryPrice!) * quantity! * direction - fee;
  }

  double get balanceDelta => switch (kind) {
    LedgerKind.deposit => amount!,
    LedgerKind.withdrawal => -amount!,
    LedgerKind.openTrade => 0,
    LedgerKind.closedTrade => realizedPnl,
  };

  void validate() {
    if (accountKey.trim().isEmpty || timestampMs <= 0) {
      throw const FormatException('هوية الدفتر أو تاريخ القيد غير صالح.');
    }
    if (kind == LedgerKind.deposit || kind == LedgerKind.withdrawal) {
      if (amount == null || !amount!.isFinite || amount! <= 0) {
        throw const FormatException('أدخل مبلغًا موجبًا صالحًا.');
      }
      return;
    }
    if (!usdQuotedSymbols.contains(symbol) || side == null ||
        quantity == null || !quantity!.isFinite || quantity! <= 0 ||
        entryPrice == null || !entryPrice!.isFinite || entryPrice! <= 0 ||
        (kind == LedgerKind.closedTrade &&
            (exitPrice == null || !exitPrice!.isFinite || exitPrice! <= 0)) ||
        (kind == LedgerKind.openTrade && exitPrice != null) ||
        !fee.isFinite || fee < 0 ||
        (openedAtMs != null && (openedAtMs! <= 0 || openedAtMs! > timestampMs)) ||
        (kind == LedgerKind.closedTrade && !realizedPnl.isFinite)) {
      throw const FormatException('تفاصيل الصفقة غير صالحة أو عملتها ليست الدولار.');
    }
  }
}

class LedgerReport {
  const LedgerReport({
    required this.entries,
    required this.trades,
    required this.openingBalance,
    required this.closingBalance,
    required this.deposits,
    required this.withdrawals,
    required this.netProfit,
    required this.wins,
    required this.losses,
    required this.profitFactor,
    required this.maxDrawdown,
    required this.bestWinStreak,
    required this.worstLossStreak,
    required this.averageTradeMinutes,
    required this.dailyPnl,
    required this.balanceSeries,
  });

  final List<LedgerEntry> entries;
  final List<LedgerEntry> trades;
  final double openingBalance;
  final double closingBalance;
  final double deposits;
  final double withdrawals;
  final double netProfit;
  final int wins;
  final int losses;
  final double? profitFactor;
  final double maxDrawdown;
  final int bestWinStreak;
  final int worstLossStreak;
  final double? averageTradeMinutes;
  final Map<DateTime, double> dailyPnl;
  final List<(int, double)> balanceSeries;

  int get tradeCount => trades.length;
  double? get winRate => tradeCount == 0 ? null : wins / tradeCount * 100;
  double? get expectancy => tradeCount == 0 ? null : netProfit / tradeCount;
}

/// Computes realized, user-recorded USD results. No price or P&L fixtures.
LedgerReport calculateLedgerReport(List<LedgerEntry> all,
    {int? startMs, int? endMs}) {
  final sorted = all.toList()..sort((a, b) {
    final date = a.timestampMs.compareTo(b.timestampMs);
    return date != 0 ? date : a.id.compareTo(b.id);
  });
  final selected = sorted.where((entry) =>
      (startMs == null || entry.timestampMs >= startMs) &&
      (endMs == null || entry.timestampMs <= endMs)).toList(growable: false);
  final opening = sorted.where((e) => startMs != null && e.timestampMs < startMs)
      .fold<double>(0, (sum, entry) => sum + entry.balanceDelta);
  final trades = selected.where((e) => e.kind == LedgerKind.closedTrade).toList(growable: false);
  var deposits = 0.0, withdrawals = 0.0, net = 0.0;
  var profits = 0.0, lossesTotal = 0.0;
  var wins = 0, losses = 0, winStreak = 0, lossStreak = 0;
  var bestWin = 0, worstLoss = 0;
  var currentBalance = opening, peakProfit = 0.0, cumulativeProfit = 0.0, drawdown = 0.0;
  var durationSum = 0.0, durationCount = 0;
  final daily = <DateTime, double>{};
  final points = <(int, double)>[];
  if (selected.isNotEmpty) points.add((selected.first.timestampMs - 1, opening));
  for (final entry in selected) {
    switch (entry.kind) {
      case LedgerKind.deposit:
        deposits += entry.amount!;
        break;
      case LedgerKind.withdrawal:
        withdrawals += entry.amount!;
        break;
      case LedgerKind.openTrade:
        break;
      case LedgerKind.closedTrade:
        final pnl = entry.realizedPnl;
        net += pnl;
        cumulativeProfit += pnl;
        peakProfit = math.max(peakProfit, cumulativeProfit);
        drawdown = math.max(drawdown, peakProfit - cumulativeProfit);
        if (pnl > 0) {
          profits += pnl;
          wins++;
          winStreak++;
          lossStreak = 0;
        } else if (pnl < 0) {
          losses++;
          lossesTotal += -pnl;
          lossStreak++;
          winStreak = 0;
        } else {
          winStreak = 0;
          lossStreak = 0;
        }
        bestWin = math.max(bestWin, winStreak);
        worstLoss = math.max(worstLoss, lossStreak);
        if (entry.openedAtMs != null) {
          durationSum += (entry.timestampMs - entry.openedAtMs!) / 60000;
          durationCount++;
        }
        final instant = DateTime.fromMillisecondsSinceEpoch(entry.timestampMs, isUtc: true);
        final day = DateTime.utc(instant.year, instant.month, instant.day);
        daily.update(day, (v) => v + pnl, ifAbsent: () => pnl);
        break;
    }
    currentBalance += entry.balanceDelta;
    points.add((entry.timestampMs, currentBalance));
  }
  return LedgerReport(
    entries: selected, trades: trades,
    openingBalance: opening, closingBalance: currentBalance,
    deposits: deposits, withdrawals: withdrawals, netProfit: net,
    wins: wins, losses: losses,
    profitFactor: lossesTotal == 0 ? (profits > 0 ? double.infinity : null)
        : profits / lossesTotal,
    maxDrawdown: drawdown,
    bestWinStreak: bestWin, worstLossStreak: worstLoss,
    averageTradeMinutes: durationCount == 0 ? null : durationSum / durationCount,
    dailyPnl: daily, balanceSeries: points,
  );
}
