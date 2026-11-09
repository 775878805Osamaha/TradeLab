import 'dart:math' as math;

import 'paper_ledger.dart';

/// Limits are supplied by the user. No trading risk percentage is assumed.
/// All amounts are USD; quantities are base-asset units, never FX lots.
class PaperRiskLimits {
  const PaperRiskLimits({
    required this.maxLossPerTradeUsd,
    this.maxDailyLossUsd,
    this.maxOpenRiskUsd,
    this.maxPositionNotionalUsd,
    this.maxTradesPerDay,
    this.minRewardRisk,
    this.cashReserveUsd = 0,
  });

  final double maxLossPerTradeUsd;
  final double? maxDailyLossUsd;
  final double? maxOpenRiskUsd;
  final double? maxPositionNotionalUsd;
  final int? maxTradesPerDay;
  final double? minRewardRisk;
  final double cashReserveUsd;
}

class PaperTradePlan {
  const PaperTradePlan({required this.side, required this.entryPrice,
    required this.stopLoss, required this.takeProfit});

  final PaperSide side;
  final double entryPrice;
  final double stopLoss;
  final double takeProfit;

  double get riskPerUnit => (entryPrice - stopLoss).abs();
  double get rewardPerUnit => (takeProfit - entryPrice).abs();
  double get rewardRisk => rewardPerUnit / riskPerUnit;
}

class PaperRiskAssessment {
  const PaperRiskAssessment({required this.maxUnits, required this.riskUsd,
    required this.notionalUsd, required this.rewardRisk,
    required this.availableCapitalUsd, required this.reasons});

  final double maxUnits;
  final double riskUsd;
  final double notionalUsd;
  final double rewardRisk;
  final double availableCapitalUsd;
  final List<String> reasons;
  bool get allowed => reasons.isEmpty;
}

/// Pure, deterministic rules shared by the order sheet and the last gate
/// before a local journal write. Does not call a broker or change limits.
class PaperRiskEngine {
  const PaperRiskEngine();

  static const _precision = 1000000.0;

  PaperRiskAssessment assess({
    required PaperTradePlan plan,
    required PaperRiskLimits limits,
    required List<LedgerEntry> entries,
    required int nowMs,
    double? requestedUnits,
  }) {
    final issues = <String>[];
    bool positive(double value) => value.isFinite && value > 0;
    bool validOptional(double? value) =>
        value == null || (value.isFinite && value > 0);

    if (!positive(limits.maxLossPerTradeUsd) ||
        !validOptional(limits.maxDailyLossUsd) ||
        !validOptional(limits.maxOpenRiskUsd) ||
        !validOptional(limits.maxPositionNotionalUsd) ||
        !validOptional(limits.minRewardRisk) ||
        !limits.cashReserveUsd.isFinite || limits.cashReserveUsd < 0 ||
        (limits.maxTradesPerDay != null && limits.maxTradesPerDay! <= 0)) {
      issues.add('حدود المخاطرة غير صالحة. راجع القيم التي أدخلتها.');
    }
    final entry = plan.entryPrice;
    final stop = plan.stopLoss;
    final target = plan.takeProfit;
    if (!positive(entry) || !positive(stop) || !positive(target) ||
        (plan.side == PaperSide.buy && !(stop < entry && target > entry)) ||
        (plan.side == PaperSide.sell && !(stop > entry && target < entry))) {
      issues.add('يجب أن يكون وقف الخسارة والهدف على الجانبين الصحيحين من سعر الدخول.');
    }
    if (nowMs <= 0) issues.add('وقت التحقق غير صالح.');
    if (requestedUnits != null && !positive(requestedUnits)) {
      issues.add('الكمية المطلوبة غير صالحة.');
    }
    if (entries.isNotEmpty && entries.any(
        (entry) => entry.accountKey != entries.first.accountKey)) {
      issues.add('قيود حسابات مختلفة مختلطة؛ أعد تحميل الدفتر الحالي.');
    }
    if (issues.isNotEmpty) {
      return PaperRiskAssessment(maxUnits: 0, riskUsd: 0,
        notionalUsd: 0, rewardRisk: 0, availableCapitalUsd: 0,
        reasons: List.unmodifiable(issues));
    }

    final rr = plan.rewardRisk;
    if (limits.minRewardRisk != null && rr < limits.minRewardRisk!) {
      issues.add('نسبة العائد إلى المخاطرة أقل من الحد الذي حددته.');
    }
    final report = calculateLedgerReport(entries);
    final openPositions = entries.where((entry) =>
        entry.kind == LedgerKind.openTrade).toList(growable: false);
    final committed = openPositions.fold<double>(0, (sum, position) =>
        sum + position.quantity! * position.entryPrice!);
    final available = math.max(0.0,
      report.closingBalance - committed - limits.cashReserveUsd);

    final utc = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
    final dayStart = DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch;
    final todaysTrades = entries.where((entry) =>
      (entry.kind == LedgerKind.openTrade || entry.kind == LedgerKind.closedTrade) &&
      (entry.openedAtMs ?? entry.timestampMs) >= dayStart &&
      (entry.openedAtMs ?? entry.timestampMs) <= nowMs).length;
    if (limits.maxTradesPerDay != null &&
        todaysTrades >= limits.maxTradesPerDay!) {
      issues.add('وصلت إلى حد عدد الصفقات اليومي.');
    }

    final todayRealized = entries.where((entry) =>
      entry.kind == LedgerKind.closedTrade &&
      entry.timestampMs >= dayStart && entry.timestampMs <= nowMs)
      .fold<double>(0, (sum, entry) => sum + entry.realizedPnl);
    final realizedLoss = math.max(0.0, -todayRealized);
    var openRisk = 0.0;
    var unknownRisk = false;
    for (final position in openPositions) {
      final stopPrice = position.stopLoss;
      if (stopPrice == null || !stopPrice.isFinite || stopPrice <= 0) {
        unknownRisk = true;
        continue;
      }
      final risk = (position.entryPrice! - stopPrice).abs() * position.quantity!;
      openRisk += risk;
    }
    if (unknownRisk && (limits.maxOpenRiskUsd != null ||
        limits.maxDailyLossUsd != null)) {
      issues.add('توجد مراكز قديمة بلا وقف خسارة مسجل؛ لا يمكن تأكيد حد المخاطرة الإجمالي.');
    }

    var allowedRisk = limits.maxLossPerTradeUsd;
    if (limits.maxDailyLossUsd != null) {
      // An overnight position can still hit its stop today. Reserve its risk
      // against today's limit as well, not just positions opened after UTC 00.
      allowedRisk = math.min(allowedRisk,
          limits.maxDailyLossUsd! - realizedLoss - openRisk);
    }
    if (limits.maxOpenRiskUsd != null) {
      allowedRisk = math.min(allowedRisk, limits.maxOpenRiskUsd! - openRisk);
    }
    var allowedNotional = available;
    if (limits.maxPositionNotionalUsd != null) {
      allowedNotional = math.min(allowedNotional,
          limits.maxPositionNotionalUsd! - committed);
    }
    if (allowedRisk <= 0) issues.add('لا توجد مخاطرة متاحة ضمن حدودك الحالية.');
    if (allowedNotional <= 0) issues.add('لا يوجد رصيد حر كافٍ دون افتراض رافعة مالية.');

    final maxByRisk = math.max(0.0, allowedRisk) / plan.riskPerUnit;
    final maxByCash = math.max(0.0, allowedNotional) / entry;
    final limit = math.min(maxByRisk, maxByCash);
    final maxUnits = limit.isFinite
        ? (limit * _precision).floorToDouble() / _precision : 0.0;
    if (maxUnits <= 0) issues.add('الحدود الحالية لا تسمح بكمية موجبة.');
    final units = requestedUnits ?? maxUnits;
    if (units > maxUnits + 0.0000000001) {
      issues.add('الكمية تتجاوز حد المخاطرة أو الرصيد المتاح.');
    }
    return PaperRiskAssessment(maxUnits: maxUnits,
      riskUsd: units * plan.riskPerUnit,
      notionalUsd: units * entry,
      rewardRisk: rr,
      availableCapitalUsd: available,
      reasons: List.unmodifiable(issues));
  }
}
