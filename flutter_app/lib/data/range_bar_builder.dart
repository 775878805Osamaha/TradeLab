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
  final List<TradeCandle> _closed = [];
  double? _open;
  double? _high;
  double? _low;
  double? _lastPrice;

  List<TradeCandle> get closed => List.unmodifiable(_closed);

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

    _lastPrice = price;
    while ((price - _open!).abs() >= priceDistance) {
      final direction = price > _open! ? 1.0 : -1.0;
      final close = _open! + direction * priceDistance;
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

/// Deterministic synthetic tick prices. VISUAL PREVIEW ONLY.
List<double> previewBidTicks() {
  var price = 55.0;
  return List<double>.generate(1800, (index) {
    price += math.sin(index * .24) * .155 +
        math.sin(index * .047) * .095 +
        (index % 87 == 0 ? -.18 : .005);
    return price;
  });
}

/// Display sizes are UI-configurable until symbol-specific cTrader pip/tick
/// parameters can be supplied. The 0.001 multiplier is NOT a broker tick size.
List<TradeCandle> previewRangeCandles(int displaySize,
    {int? throughTick}) {
  final builder = RangeBarBuilder(displaySize * .001);
  final ticks = previewBidTicks();
  final cutoff = (throughTick ?? ticks.length).clamp(1, ticks.length);
  for (final tick in ticks.take(cutoff)) {
    builder.appendBidTick(tick);
  }
  return builder.snapshot();
}
