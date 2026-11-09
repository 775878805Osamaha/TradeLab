import 'market_api.dart';

/// Merge chronologically verified broker candles without inventing missing
/// minutes or silently replacing historical OHLC from a second response.
/// A broker's market may be closed for many minutes, so a timestamp gap is
/// not itself proof of corrupted data; conflicting overlap *is*.
class CTraderCandleStitcher {
  static List<MarketBar> append(
    List<MarketBar> existing,
    List<MarketBar> recent,
  ) {
    validateBars(existing);
    validateBars(recent);
    if (existing.isEmpty) return List<MarketBar>.unmodifiable(recent);
    if (recent.isEmpty) return existing;

    final known = <int, MarketBar>{
      for (final bar in existing) bar.timestamp: bar,
    };
    final next = <MarketBar>[...existing];
    final latest = existing.last.timestamp;
    for (final bar in recent) {
      final prior = known[bar.timestamp];
      if (prior != null) {
        if (prior.candle.open != bar.candle.open ||
            prior.candle.high != bar.candle.high ||
            prior.candle.low != bar.candle.low ||
            prior.candle.close != bar.candle.close) {
          throw const MarketDataException(
              'تغيّرت قيم شمعة cTrader تاريخية بين طلبين؛ '
              'أوقفنا التحديث حتى يُراجع المصدر.');
        }
      } else if (bar.timestamp > latest) {
        next.add(bar);
      } else {
        // The broker returned an old candle missing from the previously
        // displayed history. Do not silently insert bars into Replay indices.
        throw const MarketDataException(
            'تاريخ cTrader غير متصل؛ ظهرت شموع قديمة لم تُحمّل سابقًا.');
      }
    }
    if (next.length > 200000) {
      throw const MarketDataException(
          'تجاوز التاريخ المحمّل حد الذاكرة. أعد فتح الشارت.');
    }
    return List<MarketBar>.unmodifiable(next);
  }
}
