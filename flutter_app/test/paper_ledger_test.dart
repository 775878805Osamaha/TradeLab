import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';

void main() {
  final day1 = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
  final day2 = DateTime.utc(2026, 10, 2).millisecondsSinceEpoch;

  LedgerEntry cash(int id, LedgerKind kind, double amount, int timestamp) =>
      LedgerEntry(id: id, accountKey: 'ctrader:101', kind: kind,
          timestampMs: timestamp, amount: amount);

  LedgerEntry trade(int id, PaperSide side, double entry, double exit,
      int timestamp, {double fee = 0}) => LedgerEntry(
        id: id, accountKey: 'ctrader:101', kind: LedgerKind.closedTrade,
        timestampMs: timestamp, symbol: 'XAUUSD', side: side,
        quantity: 2, entryPrice: entry, exitPrice: exit, fee: fee,
        openedAtMs: timestamp - const Duration(hours: 1).inMilliseconds);

  test('separates deposits/withdrawals from realized profit', () {
    final result = calculateLedgerReport([
      cash(1, LedgerKind.deposit, 1000, day1),
      trade(2, PaperSide.buy, 100, 110, day1 + 1000, fee: 2),
      trade(3, PaperSide.sell, 120, 130, day2, fee: 1),
      cash(4, LedgerKind.withdrawal, 100, day2 + 1000),
    ]);
    expect(result.deposits, 1000);
    expect(result.withdrawals, 100);
    expect(result.netProfit, -3);
    expect(result.closingBalance, 897);
    expect(result.winRate, 50);
    expect(result.profitFactor, closeTo(18 / 21, .00001));
    expect(result.bestWinStreak, 1);
    expect(result.worstLossStreak, 1);
    expect(result.averageTradeMinutes, 60);
    expect(result.dailyPnl.length, 2);
    expect(result.maxDrawdown, 21);
  });

  test('period opening balance contains only earlier records', () {
    final report = calculateLedgerReport([
      cash(1, LedgerKind.deposit, 200, day1),
      trade(2, PaperSide.buy, 10, 15, day2),
    ], startMs: day2);
    expect(report.openingBalance, 200);
    expect(report.deposits, 0);
    expect(report.netProfit, 10);
    expect(report.closingBalance, 210);
    expect(report.entries.length, 1);
  });

  test('rejects non-USD quote currencies, invalid fees, and future open time', () {
    expect(() => LedgerEntry(id: 0, accountKey: 'a',
      kind: LedgerKind.closedTrade, timestampMs: day2,
      symbol: 'USDJPY', side: PaperSide.buy, quantity: 1,
      entryPrice: 150, exitPrice: 151).validate(), throwsFormatException);
    expect(() => trade(1, PaperSide.buy, 100, 110, day2, fee: -1)
        .validate(), throwsFormatException);
    expect(() => LedgerEntry(id: 0, accountKey: 'a',
      kind: LedgerKind.withdrawal, timestampMs: day2,
      amount: double.nan).validate(), throwsFormatException);
  });

  test('empty journal never invents balances or performance', () {
    final report = calculateLedgerReport([]);
    expect(report.entries, isEmpty);
    expect(report.tradeCount, 0);
    expect(report.winRate, isNull);
    expect(report.profitFactor, isNull);
    expect(report.balanceSeries, isEmpty);
  });
}
