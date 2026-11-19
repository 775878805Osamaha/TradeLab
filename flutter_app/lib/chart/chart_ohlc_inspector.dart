import '../data/tradelab_data.dart';
import 'chart_viewport.dart';

/// One source-candle snapshot for the OHLC inspection strip.
///
/// [candles] is the CURRENT displayed chart list. The caller has already
/// bounded that list to the Replay prefix or reconstructed authentic BID
/// Range bars. Never look up raw/future candles from a separate archive.
class ChartOhlcSelection {
  const ChartOhlcSelection({
    required this.index,
    required this.utcTimestampMs,
    required this.candle,
  });

  final int index;
  final int utcTimestampMs;
  final TradeCandle candle;

  bool get rising => candle.close >= candle.open;

  /// Keep the price itself as the source of truth; this is presentation only.
  String formatPrice(double value, int digits) =>
      value.toStringAsFixed(digits.clamp(0, 8));

  String get changeDirection => rising ? '▲' : '▼';

  double? get changePercent {
    if (!candle.open.isFinite || !candle.close.isFinite ||
        candle.open == 0) return null;
    final value = (candle.close - candle.open) / candle.open.abs() * 100;
    return value.isFinite ? value : null;
  }
}

class ChartOhlcInspector {
  const ChartOhlcInspector._();

  /// The price guide and the OHLC display MUST resolve to the same candle.
  /// A touch in blank right-hand future space never returns the latest candle
  /// as a misleading substitute. In Replay, candleCount is prefix-only.
  static ChartOhlcSelection? atCrosshair({
    required ChartViewport viewport,
    required double touchX,
    required double plotWidth,
    required List<TradeCandle> candles,
    required List<int> timestampsUtcMs,
  }) {
    if (candles.isEmpty || timestampsUtcMs.length < candles.length) {
      return null;
    }
    final snapped = ChartCrosshairSnap.resolve(
      viewport: viewport,
      touchX: touchX,
      plotWidth: plotWidth,
      candleCount: candles.length,
    );
    final index = snapped.index;
    if (index == null || index < 0 || index >= candles.length ||
        index >= timestampsUtcMs.length) return null;
    final utcMs = timestampsUtcMs[index];
    if (utcMs <= 0) return null;
    return ChartOhlcSelection(
      index: index,
      utcTimestampMs: utcMs,
      candle: candles[index],
    );
  }
}
