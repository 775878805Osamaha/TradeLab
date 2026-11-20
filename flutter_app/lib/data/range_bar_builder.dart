import 'dart:math' as math;

import 'tradelab_data.dart';

/// Incremental price-distance bars for ordered BID ticks.
///
/// Produces a completed bar only after an incoming tick has reached the exact
/// closing boundary. Large gaps can close more than one bar. Bars are never
/// calculated from future ticks or from pre-aggregated OHLC candles.
///
/// This is an integration-ready *reference algorithm*, not yet a promise of
/// identical results to cTrader/TradingView's proprietary Range semantics.
class RangeBarBuilder {
  RangeBarBuilder(this.priceDistance) {
    if (!priceDistance.isFinite || priceDistance <= 0) {
      throw ArgumentError.value(priceDistance, 'priceDistance', 'Must be finite and positive');
    }
  }

  final double priceDistance;

  // One broker tick may legitimately cross several Range prices. A single
  // malformed distance or extreme price jump must not create an unbounded
  // number of candles on the chart/UI isolate.
  static const maxBarsPerSingleTick = 100000;
  final List<TradeCandle> _closed = [];
  // The timeline worker can transfer ownership of this list exactly once.
  // After transfer the builder must not mutate its published chart snapshot.
  bool _sealed = false;
  bool _sealedForming = false;
  double? _open;
  double? _high;
  double? _low;
  double? _lastPrice;

  List<TradeCandle> get closed => List.unmodifiable(
      _sealedForming ? _closed.take(_closed.length - 1) : _closed);

  /// O(1) completion count for timestamp/tick-index tracking.
  int get closedCount => _closed.length - (_sealedForming ? 1 : 0);

  TradeCandle? get forming => _open == null
      ? null
      : TradeCandle(_open!, _high!, _low!, _lastPrice!);

  void appendBidTick(double price) {
    if (_sealed) {
      throw StateError('Sealed Range history cannot accept more BID ticks');
    }
    if (!price.isFinite || price <= 0) {
      throw ArgumentError.value(price, 'price', 'BID price must be finite and positive');
    }
    if (_open == null) {
      _open = _high = _low = _lastPrice = price;
      return;
    }

    final distanceToPrice = (price - _open!).abs();
    final crossing = distanceToPrice / priceDistance;
    if (!crossing.isFinite || crossing > maxBarsPerSingleTick) {
      // Reject this one tick before mutating the existing confirmed bars.
      // Do not emit a truncated history that Replay might treat as complete.
      throw StateError('Range BID gap would create too many bars from one tick');
    }
    if (distanceToPrice >= priceDistance) {
      final firstStep = _open! + (price > _open! ? priceDistance : -priceDistance);
      if (firstStep == _open! || !firstStep.isFinite) {
        throw StateError('Range distance is below the price precision');
      }
    }
    _lastPrice = price;
    while ((price - _open!).abs() >= priceDistance) {
      final direction = price > _open! ? 1.0 : -1.0;
      final close = _open! + direction * priceDistance;
      if (!close.isFinite || close == _open!) {
        throw StateError('Range price step cannot advance at this precision');
      }
      _high = math.max(_high!, close);
      _low = math.min(_low!, close);
      _closed.add(TradeCandle(_open!, _high!, _low!, close));
      _open = _high = _low = close;
    }
    _high = math.max(_high!, price);
    _low = math.min(_low!, price);
  }

  /// Read-only-in-practice legacy snapshot: always returns an independent
  /// list, so an incremental builder may safely accept more verified ticks.
  List<TradeCandle> snapshot({bool includeForming = true}) => [
        ...(_sealedForming
            ? _closed.take(_closed.length - 1)
            : _closed),
        if (includeForming && forming != null) forming!,
      ];

  /// One-time finalization for a RangeBarTimeline worker. Reuse the already
  /// allocated closed-bar array instead of copying all 100k+ candle references
  /// into a second growable list at the end of every historical rebuild.
  ///
  /// The last forming bar remains visible on the live chart but is not a
  /// closed/executable Replay bar. After transfer this builder is sealed:
  /// neither further BID events nor another transfer can mutate published
  /// chart history. Existing snapshot() remains independent for callers
  /// that deliberately keep processing new ticks.
  List<TradeCandle> sealSnapshot({bool includeForming = true}) {
    if (_sealed) {
      throw StateError('Range snapshot has already been transferred');
    }
    final unfinished = includeForming ? forming : null;
    _sealed = true;
    _sealedForming = unfinished != null;
    if (unfinished != null) _closed.add(unfinished);
    return _closed;
  }
}
