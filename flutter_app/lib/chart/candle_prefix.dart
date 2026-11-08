import 'dart:collection';
import 'dart:math' as math;

import '../data/tradelab_data.dart';

/// Read-only O(1) view of the candles already revealed in Replay.
/// Avoids copying thousands of future candles on every drag or pinch.
class CandlePrefix extends ListBase<TradeCandle> {
  CandlePrefix(List<TradeCandle> source, int through)
      : _source = source,
        _through = math.max(0, math.min(through, source.length));

  final List<TradeCandle> _source;
  final int _through;

  @override
  int get length => _through;

  @override
  set length(int value) => throw UnsupportedError('Replay candles are read-only.');

  @override
  TradeCandle operator [](int index) {
    if (index < 0 || index >= _through) {
      throw RangeError.index(index, this);
    }
    return _source[index];
  }

  @override
  void operator []=(int index, TradeCandle value) =>
      throw UnsupportedError('Replay candles are read-only.');
}
