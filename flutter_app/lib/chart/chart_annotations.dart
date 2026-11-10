/// Drawing objects use candle positions and real market prices, not pixel
/// coordinates. Historical pagination shifts indices but never prices.
enum ChartDrawingTool {
  horizontal, trendLine, fibonacci,
  ray, extendedLine, horizontalRay, verticalLine, parallelChannel;

  bool get oneAnchor =>
      this == horizontalRay || this == verticalLine;
  bool get threeAnchors => this == parallelChannel;
}
enum ChartAnchorEndpoint { start, end, offset }

/// Match TradingView's optional OHLC magnet while retaining free placement.
enum ChartMagnetMode { off, weak, strong }

/// Price-axis snapping is based on the *displayed* real candle, not a made-up
/// price grid. Weak magnet only engages within [weakPriceTolerance].
double snapDrawingPrice({
  required double requestedPrice,
  required List<double> ohlc,
  required ChartMagnetMode mode,
  required double weakPriceTolerance,
}) {
  if (mode == ChartMagnetMode.off || ohlc.isEmpty) return requestedPrice;
  var nearest = ohlc.first;
  for (final value in ohlc.skip(1)) {
    if ((value - requestedPrice).abs() <
        (nearest - requestedPrice).abs()) nearest = value;
  }
  if (mode == ChartMagnetMode.weak &&
      (nearest - requestedPrice).abs() > weakPriceTolerance) {
    return requestedPrice;
  }
  return nearest;
}

class ChartAnchor {
  const ChartAnchor(this.index, this.price);

  final int index;
  final double price;

  ChartAnchor shifted(int olderCount) =>
      ChartAnchor(index + olderCount, price);

  ChartAnchor moved(int bars, double priceDelta) =>
      ChartAnchor(index + bars, price + priceDelta);
}

class ChartPattern {
  const ChartPattern({
    required this.tool,
    required this.start,
    required this.end,
    this.offsetAnchor,
    this.colorValue = 0xFF3467E9,
    this.strokeWidth = 1.5,
    this.showLabels = true,
  });

  final ChartDrawingTool tool;
  final ChartAnchor start;
  final ChartAnchor end;
  /// Third source-price/bar anchor, only for a parallel channel.
  final ChartAnchor? offsetAnchor;
  final int colorValue;
  final double strokeWidth;
  final bool showLabels;

  /// Fibonacci prices are based on the two selected historical prices only.
  /// No future bars are examined to compute these levels.
  static const fibonacciRatios = <double>[
    0, .236, .382, .5, .618, .786, 1,
  ];

  double fibonacciPrice(double ratio) =>
      start.price + (end.price - start.price) * ratio;

  ChartPattern shifted(int olderCount) => ChartPattern(
      tool: tool,
      start: start.shifted(olderCount),
      end: end.shifted(olderCount),
      offsetAnchor: offsetAnchor?.shifted(olderCount),
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      showLabels: showLabels);

  ChartPattern reanchored(int startIndex, int endIndex,
      {int? offsetIndex}) => ChartPattern(
      tool: tool,
      start: ChartAnchor(startIndex, start.price),
      end: ChartAnchor(endIndex, end.price),
      offsetAnchor: offsetAnchor == null ? null
          : ChartAnchor(offsetIndex ?? offsetAnchor!.index, offsetAnchor!.price),
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      showLabels: showLabels);

  ChartPattern moved(int bars, double priceDelta) => ChartPattern(
      tool: tool,
      start: start.moved(bars, priceDelta),
      end: end.moved(bars, priceDelta),
      offsetAnchor: offsetAnchor?.moved(bars, priceDelta),
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      showLabels: showLabels);

  /// Edit one real price/bar anchor without shifting the other endpoint.
  /// This also preserves the drawing style and Fibonacci level direction.
  ChartPattern withEndpoint(ChartAnchorEndpoint endpoint, ChartAnchor anchor) =>
      ChartPattern(
        tool: tool,
        start: endpoint == ChartAnchorEndpoint.start ? anchor : start,
        end: endpoint == ChartAnchorEndpoint.end ||
                (tool.oneAnchor && endpoint == ChartAnchorEndpoint.start)
            ? anchor : end,
        offsetAnchor: endpoint == ChartAnchorEndpoint.offset
            ? anchor : offsetAnchor,
        colorValue: colorValue,
        strokeWidth: strokeWidth,
        showLabels: showLabels,
      );

  ChartPattern styled({int? colorValue, double? strokeWidth, bool? showLabels}) =>
      ChartPattern(
        tool: tool,
        start: start,
        end: end,
        offsetAnchor: offsetAnchor,
        colorValue: colorValue ?? this.colorValue,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        showLabels: showLabels ?? this.showLabels,
      );

  /// A replayed historical series may show only a prefix. Never display an
  /// annotation whose endpoint refers to an as-yet-unrevealed candle.
  bool visibleAt(int revealedCount) =>
      start.index < revealedCount && end.index < revealedCount &&
      (offsetAnchor == null || offsetAnchor!.index < revealedCount);
}
