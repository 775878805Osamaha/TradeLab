import 'dart:math' as math;

import 'replay_lab_bridge.dart';
import 'replay_observed_trade.dart';
import 'replay_trade_evaluator.dart';

class ReplaySessionRow {
  const ReplaySessionRow({required this.signal, required this.result});

  final ReplayObservedSignal signal;
  final ReplayObservedResult result;
}

class ReplaySessionReport {
  const ReplaySessionReport({required this.rows, required this.finished,
    required this.pending, required this.open, required this.unavailable,
    required this.wins, required this.totalGrossR,
    required this.totalNetR, required this.maxDrawdownR});

  final List<ReplaySessionRow> rows;
  final int finished;
  final int pending;
  final int open;
  final int unavailable;
  final int wins;
  final double totalGrossR;
  /// Null if even one completed signal lacks an execution-cost assumption.
  final double? totalNetR;
  final double maxDrawdownR;

  double? get winRate => finished == 0 ? null : wins * 100 / finished;
}

/// Read-only, session-scoped study. It never changes OHLC, the Replay cursor,
/// the local paper ledger, or any real broker account. R is NOT cash equity.
class ReplaySessionStudy {
  const ReplaySessionStudy();

  static const maxSignals = 100;
  static const _tracker = ReplayObservedTradeTracker();

  /// Require a chronological, non-overlapping sequence of confirmed outcomes.
  /// This prevents an apparent multi-trade performance curve from counting
  /// several simultaneous bets as independently reinvested trades.
  void validateNext({required List<ReplayObservedSignal> existing,
    required ReplayObservedSignal next,
    required ReplayLabSnapshot snapshot}) {
    if (existing.length >= maxSignals) {
      throw const FormatException('وصلت إلى حد 100 إشارة في هذه الجلسة.');
    }
    if (next.accountKey != snapshot.accountKey ||
        next.symbol != snapshot.symbol ||
        next.timeframe != snapshot.timeframe ||
        existing.any((item) => item.accountKey != next.accountKey ||
          item.symbol != next.symbol || item.timeframe != next.timeframe)) {
      throw const FormatException('تغيّر نطاق الجلسة؛ لا يمكن خلط حسابات أو رموز أو أطر مختلفة.');
    }
    if (snapshot.bars.isEmpty ||
        next.signalTimestamp != snapshot.bars.last.timestamp ||
        !_tracker.inspect(signal: next, snapshot: snapshot).available) {
      throw const FormatException('لا يمكن تسجيل إشارة غير مثبتة عند آخر شمعة Replay ظاهرة.');
    }
    for (var i = 1; i < existing.length; i++) {
      if (existing[i].signalTimestamp <= existing[i - 1].signalTimestamp) {
        throw const FormatException('ترتيب سجل الجلسة غير صالح.');
      }
    }
    if (existing.isEmpty) return;
    final previous = existing.last;
    if (next.signalTimestamp <= previous.signalTimestamp) {
      throw const FormatException('قدّم Replay بعد الإشارة السابقة قبل تسجيل إشارة أخرى.');
    }
    final previousResult = _tracker.inspect(
      signal: previous, snapshot: snapshot);
    if (!previousResult.available) {
      throw const FormatException('بيانات الإشارة السابقة غير متاحة أو تغيّرت؛ لا يمكن متابعة الجلسة.');
    }
    if (previousResult.outcome!.status != ReplayTradeStatus.stopped &&
        previousResult.outcome!.status != ReplayTradeStatus.targeted) {
      throw const FormatException('انتظر حسم الصفقة التدريبية السابقة قبل بدء أخرى.');
    }
    if (previousResult.outcome!.exitBarIndex == null ||
        snapshot.bars[previousResult.outcome!.exitBarIndex!].timestamp >=
            next.signalTimestamp) {
      throw const FormatException('لا يمكن تسجيل إشارة أثناء شمعة خروج الصفقة السابقة.');
    }
  }

  ReplaySessionReport summarize({required List<ReplayObservedSignal> signals,
    required ReplayLabSnapshot snapshot}) {
    final rows = <ReplaySessionRow>[];
    var finished = 0, pending = 0, opened = 0, unavailable = 0, wins = 0;
    var grossR = 0.0, netR = 0.0, peakR = 0.0, maxDrawdownR = 0.0;
    var allCompletedHaveCosts = true;

    for (final signal in signals) {
      final result = _tracker.inspect(signal: signal, snapshot: snapshot);
      rows.add(ReplaySessionRow(signal: signal, result: result));
      final outcome = result.outcome;
      if (outcome == null) {
        unavailable++;
        continue;
      }
      switch (outcome.status) {
        case ReplayTradeStatus.pending:
          pending++;
          break;
        case ReplayTradeStatus.open:
          opened++;
          break;
        case ReplayTradeStatus.stopped:
        case ReplayTradeStatus.targeted:
          finished++;
          final r = outcome.rMultiple!;
          grossR += r;
          wins += r > 0 ? 1 : 0;
          peakR = math.max(peakR, grossR);
          maxDrawdownR = math.max(maxDrawdownR, peakR - grossR);
          if (outcome.netRMultiple == null) {
            allCompletedHaveCosts = false;
          } else {
            netR += outcome.netRMultiple!;
          }
          break;
      }
    }
    return ReplaySessionReport(rows: List.unmodifiable(rows),
      finished: finished, pending: pending, open: opened,
      unavailable: unavailable, wins: wins, totalGrossR: grossR,
      totalNetR: finished > 0 && allCompletedHaveCosts ? netR : null,
      maxDrawdownR: maxDrawdownR);
  }
}
