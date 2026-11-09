import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/paper/paper_risk_engine.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9, 12).millisecondsSinceEpoch;
  LedgerEntry deposit(double usd) => LedgerEntry(id: 1,
    accountKey: 'local:guest', kind: LedgerKind.deposit,
    timestampMs: now - 3600000, amount: usd);
  const long = PaperTradePlan(side: PaperSide.buy,
    entryPrice: 100, stopLoss: 95, takeProfit: 110);
  const short = PaperTradePlan(side: PaperSide.sell,
    entryPrice: 100, stopLoss: 105, takeProfit: 90);
  const engine = PaperRiskEngine();

  test('sizes by tighter of max loss and genuinely uncommitted capital', () {
    final byRisk = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50),
      entries: [deposit(2000)], nowMs: now);
    expect(byRisk.allowed, isTrue);
    expect(byRisk.maxUnits, 10);
    expect(byRisk.riskUsd, 50);
    expect(byRisk.rewardRisk, 2);

    final byCash = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50),
      entries: [deposit(300)], nowMs: now);
    expect(byCash.maxUnits, 3);
    expect(byCash.riskUsd, 15);
    final tooLarge = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50),
      entries: [deposit(300)], nowMs: now, requestedUnits: 4);
    expect(tooLarge.allowed, isFalse);
  });

  test('handles short positions, wrong-sided stops and target rules', () {
    final okay = engine.assess(plan: short,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 20,
        minRewardRisk: 1.5), entries: [deposit(1000)], nowMs: now);
    expect(okay.allowed, isTrue);
    expect(okay.maxUnits, 4);
    final bad = engine.assess(plan: const PaperTradePlan(side: PaperSide.sell,
      entryPrice: 100, stopLoss: 90, takeProfit: 110),
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 20),
      entries: [deposit(1000)], nowMs: now);
    expect(bad.allowed, isFalse);
    final rr = engine.assess(plan: short,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 20,
        minRewardRisk: 3), entries: [deposit(1000)], nowMs: now);
    expect(rr.allowed, isFalse);
  });

  test('reserves open notional and counts existing stop risk', () {
    final open = LedgerEntry(id: 2, accountKey: 'local:guest',
      kind: LedgerKind.openTrade, timestampMs: now - 1000,
      openedAtMs: now - 1000, symbol: 'XAUUSD', side: PaperSide.buy,
      quantity: 5, entryPrice: 100, stopLoss: 95, takeProfit: 110);
    final assessment = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxOpenRiskUsd: 30, maxDailyLossUsd: 40),
      entries: [deposit(1000), open], nowMs: now);
    expect(assessment.allowed, isTrue);
    expect(assessment.availableCapitalUsd, 500);
    expect(assessment.maxUnits, 1); // $5 risk remains under open cap.
  });

  test('daily loss and daily trade count restrict new entries', () {
    final closed = LedgerEntry(id: 3, accountKey: 'local:guest',
      kind: LedgerKind.closedTrade, timestampMs: now - 1000,
      openedAtMs: now - 100000, symbol: 'XAUUSD', side: PaperSide.buy,
      quantity: 2, entryPrice: 100, exitPrice: 90);
    final limited = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxDailyLossUsd: 25), entries: [deposit(1000), closed],
      nowMs: now);
    expect(limited.maxUnits, 1); // $20 realized loss leaves $5.
    final countBlocked = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxTradesPerDay: 1), entries: [deposit(1000), closed],
      nowMs: now);
    expect(countBlocked.allowed, isFalse);
  });

  test('aggregate notional cap subtracts already committed positions', () {
    final open = LedgerEntry(id: 4, accountKey: 'local:guest',
      kind: LedgerKind.openTrade, timestampMs: now - 1000,
      openedAtMs: now - 1000, symbol: 'XAUUSD', side: PaperSide.buy,
      quantity: 5, entryPrice: 100, stopLoss: 95, takeProfit: 110);
    final capped = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxPositionNotionalUsd: 600),
      entries: [deposit(2000), open], nowMs: now);
    expect(capped.allowed, isTrue);
    expect(capped.maxUnits, 1, reason: '600 USD cap minus 500 USD already open');
    expect(capped.notionalUsd, 100);

    final exhausted = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxPositionNotionalUsd: 500),
      entries: [deposit(2000), open], nowMs: now);
    expect(exhausted.allowed, isFalse);
    expect(exhausted.maxUnits, 0);
  });

  test('daily risk budget also reserves overnight positions that can stop today', () {
    final overnight = LedgerEntry(id: 5, accountKey: 'local:guest',
      kind: LedgerKind.openTrade, timestampMs: now - 86400000,
      openedAtMs: now - 86400000, symbol: 'XAUUSD', side: PaperSide.buy,
      quantity: 5, entryPrice: 100, stopLoss: 95, takeProfit: 110);
    final capped = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxDailyLossUsd: 30), entries: [deposit(2000), overnight], nowMs: now);
    expect(capped.allowed, isTrue);
    expect(capped.maxUnits, 1, reason: 'overnight 25 USD stop risk reserves the daily budget');

    final exhausted = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50,
        maxDailyLossUsd: 25), entries: [deposit(2000), overnight], nowMs: now);
    expect(exhausted.allowed, isFalse);
  });

  test('cannot claim capped aggregate risk with legacy unknown stops', () {
    final legacy = LedgerEntry(id: 2, accountKey: 'local:guest',
      kind: LedgerKind.openTrade, timestampMs: now - 1000,
      symbol: 'XAUUSD', side: PaperSide.buy,
      quantity: 1, entryPrice: 100);
    final result = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 10,
        maxDailyLossUsd: 30), entries: [deposit(1000), legacy], nowMs: now);
    expect(result.allowed, isFalse);
  });

  test('no deposited funds is never treated as a funded demo account', () {
    final result = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50),
      entries: const [], nowMs: now);
    expect(result.allowed, isFalse);
    expect(result.maxUnits, 0);
  });

  test('mixed account ledger entries fail closed instead of sharing cash', () {
    final otherAccount = LedgerEntry(id: 2, accountKey: 'ctrader:other',
      kind: LedgerKind.deposit, timestampMs: now - 1000, amount: 10000);
    final result = engine.assess(plan: long,
      limits: const PaperRiskLimits(maxLossPerTradeUsd: 50),
      entries: [deposit(1000), otherAccount], nowMs: now);
    expect(result.allowed, isFalse);
    expect(result.maxUnits, 0);
  });
}
