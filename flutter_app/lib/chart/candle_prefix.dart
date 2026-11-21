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

/// One-entry cache for the immutable, *revealed* broker/Range candle prefix.
///
/// Android pan, pinch and drawing repaints must not allocate a fresh
/// CandlePrefix for the same source and Replay cutoff: a fresh list identity
/// invalidates ChartPriceScaleCache even when no source bar has changed.
/// The source list is published as an immutable snapshot; replacing it or
/// revealing/rewinding a bar always creates a new bounded prefix. An old
/// prefix keeps its original cutoff and never exposes a hidden future bar.
///
/// O(1) work and one retained prefix, not an accumulating archive cache.
class CandlePrefixCache {
  List<TradeCandle>? _source;
  int? _sourceLength;
  int? _through;
  CandlePrefix? _visible;

  CandlePrefix resolve(List<TradeCandle> source, int through) {
    final bounded = math.max(0, math.min(through, source.length));
    final cached = _visible;
    if (cached != null && identical(_source, source) &&
        _sourceLength == source.length && _through == bounded) {
      return cached;
    }
    final visible = CandlePrefix(source, bounded);
    _source = source;
    _sourceLength = source.length;
    _through = bounded;
    _visible = visible;
    return visible;
  }

  void clear() {
    _source = null;
    _sourceLength = null;
    _through = null;
    _visible = null;
  }
}
