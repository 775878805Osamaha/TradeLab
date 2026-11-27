import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'market_api.dart';
import 'market_history_budget.dart';
import 'tradelab_data.dart';

/// Immutable, source-only historical prepend. The three resulting lists
/// describe one snapshot so Flutter never sees bars from one archive and
/// candle/timestamp axes from a different archive.
class OlderCandlePrependResult {
  const OlderCandlePrependResult({
    required this.prefix,
    required this.bars,
    required this.candles,
    required this.timestamps,
  });

  final List<MarketBar> prefix;
  final List<MarketBar> bars;
  final List<TradeCandle> candles;
  final List<int> timestamps;
}

typedef _OlderCandlePrependInput = ({
  List<MarketBar> existing,
  List<MarketBar> older,
});

OlderCandlePrependResult _prepareOlderCandlePrependWorker(
    _OlderCandlePrependInput input) =>
    OlderCandlePrepend.prepare(
      existing: input.existing, older: input.older);

/// Heavy historical OHLC prepends happen during touch-driven left-edge paging.
/// For a 100k+ local archive, sorting a provider page then creating three
/// full-size lists on Flutter's UI isolate can interrupt gestures.
///
/// This helper only rearranges verified source bars; it does not insert bars
/// into gaps, request a broker, change prices or advance a Replay cutoff.
class OlderCandlePrepend {
  const OlderCandlePrepend._();

  static const minOffloadBars = 5000;

  static bool shouldOffload({
    required int existingCount,
    required int incomingCount,
  }) => !kIsWeb && incomingCount > 0 &&
      (existingCount >= minOffloadBars ||
       incomingCount >= minOffloadBars);

  static Future<OlderCandlePrependResult> prepareAsync({
    required List<MarketBar> existing,
    required List<MarketBar> older,
  }) async {
    if (!shouldOffload(
        existingCount: existing.length,
        incomingCount: older.length)) {
      return prepare(existing: existing, older: older);
    }
    return compute<_OlderCandlePrependInput, OlderCandlePrependResult>(
      _prepareOlderCandlePrependWorker,
      (existing: existing, older: older),
      debugLabel: 'tradelab-older-verified-ohlc-prepend');
  }

  /// Normalize a possibly unordered provider page and preserve its original
  /// timestamp gaps. Identical duplicate broker bars may collapse; conflicting
  /// OHLC values at the same source timestamp must never silently win.
  static OlderCandlePrependResult prepare({
    required List<MarketBar> existing,
    required List<MarketBar> older,
  }) {
    if (existing.isEmpty) {
      throw ArgumentError('Cannot prepend older history to an empty chart');
    }
    MarketHistoryBudget.requireCapacity(existing.length);
    if (older.isEmpty) {
      return OlderCandlePrependResult(
        prefix: const <MarketBar>[],
        bars: existing,
        candles: const <TradeCandle>[],
        timestamps: const <int>[],
      );
    }

    final earliest = existing.first.timestamp;
    final latest = existing.last.timestamp;
    final byTimestamp = <int, MarketBar>{};
    for (final bar in older) {
      // A provider may repeat an existing closed candle at the boundary or
      // anywhere inside a previously verified history. Skipping a conflicting
      // overlap silently would leave Replay showing disputed source OHLC.
      // The archive is strictly timestamp-ascending: use lower-bound lookup
      // instead of scanning 120k+ existing candles for every older page.
      if (bar.timestamp >= earliest) {
        if (bar.timestamp <= latest) {
          var low = 0;
          var high = existing.length;
          while (low < high) {
            final middle = low + (high - low) ~/ 2;
            if (existing[middle].timestamp < bar.timestamp) {
              low = middle + 1;
            } else {
              high = middle;
            }
          }
          if (low < existing.length &&
              existing[low].timestamp == bar.timestamp) {
            final original = existing[low].candle;
            final repeated = bar.candle;
            if (original.open != repeated.open ||
                original.high != repeated.high ||
                original.low != repeated.low ||
                original.close != repeated.close ||
                conflictingKnownVolume(original, repeated)) {
              throw const MarketDataException(
                  'تعارض في قيم شمعة محفوظة عند تحميل تاريخ أقدم؛ '
                  'أوقفنا الدمج لحماية الشارت وReplay.');
            }
          }
        }
        // A timestamp inside a source gap is not proof that the active
        // archive can be rewritten. Retain its real gap, as before.
        continue;
      }
      final previous = byTimestamp[bar.timestamp];
      if (previous != null) {
        final left = previous.candle;
        final right = bar.candle;
        if (left.open != right.open || left.high != right.high ||
            left.low != right.low || left.close != right.close ||
            conflictingKnownVolume(left, right)) {
          throw const MarketDataException(
            'تعارض في قيم الشموع الأقدم لنفس وقت المصدر؛ '
            'تم إيقاف الدمج لحماية Replay.');
        }
        if (left.volume == null && right.volume != null) {
          byTimestamp[bar.timestamp] = bar;
        }
        continue;
      }
      byTimestamp[bar.timestamp] = bar;
    }
    if (byTimestamp.isEmpty) {
      return OlderCandlePrependResult(
        prefix: const <MarketBar>[],
        bars: existing,
        candles: const <TradeCandle>[],
        timestamps: const <int>[],
      );
    }
    // Check before allocating three full-sized chart/Replay arrays.
    MarketHistoryBudget.requireCapacity(existing.length + byTimestamp.length);
    final prefix = byTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    validateBars(prefix);
    final combined = <MarketBar>[...prefix, ...existing];
    // The archive is already verified by its provider/cache. The new
    // exclusive prefix is independently validated above. Avoid a second
    // full-archive validation pass on every left-edge request.
    final candles = List<TradeCandle>.generate(
      combined.length, (i) => combined[i].candle, growable: false);
    final timestamps = List<int>.generate(
      combined.length, (i) => combined[i].timestamp, growable: false);
    return OlderCandlePrependResult(
      prefix: prefix,
      bars: combined,
      candles: candles,
      timestamps: timestamps,
    );
  }
}
