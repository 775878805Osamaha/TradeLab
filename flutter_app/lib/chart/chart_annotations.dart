/// Drawing objects use candle positions and real market prices, not pixel
/// coordinates. Historical pagination shifts indices but never prices.
enum ChartDrawingTool { horizontal, trendLine, fibonacci }

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
    this.colorValue = 0xFF3467E9,
    this.strokeWidth = 1.5,
    this.showLabels = true,
  });

  final ChartDrawingTool tool;
  final ChartAnchor start;
  final ChartAnchor end;
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
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      showLabels: showLabels);

  ChartPattern moved(int bars, double priceDelta) => ChartPattern(
      tool: tool,
      start: start.moved(bars, priceDelta),
      end: end.moved(bars, priceDelta),
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      showLabels: showLabels);

  ChartPattern styled({int? colorValue, double? strokeWidth, bool? showLabels}) =>
      ChartPattern(
        tool: tool,
        start: start,
        end: end,
        colorValue: colorValue ?? this.colorValue,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        showLabels: showLabels ?? this.showLabels,
      );

  /// A replayed historical series may show only a prefix. Never display an
  /// annotation whose endpoint refers to an as-yet-unrevealed candle.
  bool visibleAt(int revealedCount) =>
      start.index < revealedCount && end.index < revealedCount;
}
