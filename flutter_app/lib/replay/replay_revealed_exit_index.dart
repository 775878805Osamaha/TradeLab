import 'dart:math' as math;
import 'dart:typed_data';

import '../data/tradelab_data.dart';

/// Bounded source-only index for finding the FIRST revealed candle that
/// touches a Replay practice trade's stop or target.
///
/// The tree is allocated for a source snapshot, but high/low leaves are
/// populated ONLY through [indexThrough]. Future candles are never read,
/// indexed, queried or used to settle a practice position.
///
/// Each node stores exact IEEE-754 extrema, not rounded ticks or invented
/// OHLC. Range charts may contain several broker-authentic closes on the
/// same timestamp; this index works with source BAR order, not wall time.
///
/// The session must discard this instance on source replacement, rewind or
/// older historical prepend. It may only reuse an immutable-by-contract,
/// source-verified candle list.
class ReplayRevealedExitIndex {
  ReplayRevealedExitIndex(this.source) {
    if (source.length > maxSourceCandles) {
      throw ArgumentError.value(
          source.length, 'source.length', 'Outside Replay chart budget');
    }
    var powerOfTwo = 1;
    while (powerOfTwo < source.length) {
      powerOfTwo <<= 1;
    }
    _base = powerOfTwo;
    _minLow = Float64List(powerOfTwo * 2)
      ..fillRange(0, powerOfTwo * 2, double.infinity);
    _maxHigh = Float64List(powerOfTwo * 2)
      ..fillRange(0, powerOfTwo * 2, double.negativeInfinity);
  }

  // The Range display may hold 250k closed candles plus ONE unclosed
  // forming bar; the latter must never be indexed as an executable close.
  static const maxSourceCandles = 250001;

  final List<TradeCandle> source;
  late final int _base;
  late final Float64List _minLow;
  late final Float64List _maxHigh;

  int _indexedThrough = 0;
  int get indexedThrough => _indexedThrough;

  /// Index only newly REVEALED source bars. A large seek fills its leaves
  /// once, then calculates parents in a single bottom-up pass O(capacity).
  /// Small increments update O(log capacity) ancestors per revealed bar.
  /// Never read any candle at index >= [completedCount].
  void indexThrough(int completedCount) {
    if (completedCount < _indexedThrough ||
        completedCount > source.length) {
      throw RangeError.range(
          completedCount, _indexedThrough, source.length);
    }
    final added = completedCount - _indexedThrough;
    if (added == 0) return;
    final start = _indexedThrough;
    for (var i = start; i < completedCount; i++) {
      final candle = source[i];
      _minLow[_base + i] = candle.low;
      _maxHigh[_base + i] = candle.high;
      if (added <= 32) {
        var node = (_base + i) ~/ 2;
        while (node > 0) {
          _minLow[node] =
              math.min(_minLow[node * 2], _minLow[node * 2 + 1]);
          _maxHigh[node] =
              math.max(_maxHigh[node * 2], _maxHigh[node * 2 + 1]);
          node ~/= 2;
        }
      }
    }
    if (added > 32) {
      for (var node = _base - 1; node >= 1; node--) {
        _minLow[node] =
            math.min(_minLow[node * 2], _minLow[node * 2 + 1]);
        _maxHigh[node] =
            math.max(_maxHigh[node * 2], _maxHigh[node * 2 + 1]);
      }
    }
    _indexedThrough = completedCount;
  }

  /// Find the first genuinely revealed source bar meeting EITHER bound.
  /// For buy: lowAtMost=SL, highAtLeast=TP.
  /// For sell: lowAtMost=TP, highAtLeast=SL.
  /// The caller resolves a same-bar SL+TP by verified OPEN gap or the
  /// default historical OHLC path (nearer extreme first; equidistant ties
  /// conservative). The index never invents a fill or reads future candles.
  int? firstCrossing({
    required int fromInclusive,
    required int throughExclusive,
    double? lowAtMost,
    double? highAtLeast,
  }) {
    if (fromInclusive < 0 || throughExclusive < fromInclusive ||
        throughExclusive > _indexedThrough) {
      throw RangeError('Replay exit query crosses unrevealed candles');
    }
    if (lowAtMost == null && highAtLeast == null) return null;
    if (lowAtMost != null && !lowAtMost.isFinite ||
        highAtLeast != null && !highAtLeast.isFinite) {
      throw ArgumentError('Replay stop/target bounds must be finite');
    }
    if (fromInclusive == throughExclusive) return null;
    return _firstCrossing(
        1, 0, _base, fromInclusive, throughExclusive,
        lowAtMost, highAtLeast);
  }

  int? _firstCrossing(int node, int left, int right,
      int fromInclusive, int throughExclusive,
      double? lowAtMost, double? highAtLeast) {
    if (left >= throughExclusive || right <= fromInclusive) return null;
    final mayHitStopOrTarget =
        (lowAtMost != null && _minLow[node] <= lowAtMost) ||
        (highAtLeast != null && _maxHigh[node] >= highAtLeast);
    if (!mayHitStopOrTarget) return null;
    if (right - left == 1) return left;
    final middle = left + (right - left) ~/ 2;
    final first = _firstCrossing(
        node * 2, left, middle,
        fromInclusive, throughExclusive, lowAtMost, highAtLeast);
    return first ?? _firstCrossing(
        node * 2 + 1, middle, right,
        fromInclusive, throughExclusive, lowAtMost, highAtLeast);
  }
}
