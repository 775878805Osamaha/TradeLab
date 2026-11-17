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
  double? _open;
  double? _high;
  double? _low;
  double? _lastPrice;

  List<TradeCandle> get closed => List.unmodifiable(_closed);

  /// O(1) completion count for timestamp/tick-index tracking.
  int get closedCount => _closed.length;

  TradeCandle? get forming => _open == null
      ? null
      : TradeCandle(_open!, _high!, _low!, _lastPrice!);

  void appendBidTick(double price) {
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

  List<TradeCandle> snapshot({bool includeForming = true}) => [
        ..._closed,
        if (includeForming && forming != null) forming!,
      ];
}
