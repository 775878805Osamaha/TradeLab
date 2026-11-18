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

    // Both verified inputs are timestamp-ascending. A streaming cursor
    // finds every overlapping closed bar in O(existing + recent) time
    // without building a 100k/200k-entry timestamp -> bar hash map on
    // each broker refresh. Validate ALL overlaps before copying the archive.
    final appended = <MarketBar>[];
    final latest = existing.last.timestamp;
    var archiveIndex = 0;
    for (final bar in recent) {
      while (archiveIndex < existing.length &&
          existing[archiveIndex].timestamp < bar.timestamp) {
        archiveIndex++;
      }
      if (archiveIndex < existing.length &&
          existing[archiveIndex].timestamp == bar.timestamp) {
        final prior = existing[archiveIndex];
        if (prior.candle.open != bar.candle.open ||
            prior.candle.high != bar.candle.high ||
            prior.candle.low != bar.candle.low ||
            prior.candle.close != bar.candle.close) {
          throw const MarketDataException(
              'تغيّرت قيم شمعة cTrader تاريخية بين طلبين؛ '
              'أوقفنا التحديث حتى يُراجع المصدر.');
        }
      } else if (bar.timestamp > latest) {
        appended.add(bar);
      } else {
        // The broker returned an old candle missing from the previously
        // displayed history. Do not silently insert bars into Replay indices.
        throw const MarketDataException(
            'تاريخ cTrader غير متصل؛ ظهرت شموع قديمة لم تُحمّل سابقًا.');
      }
    }
    if (existing.length + appended.length > 200000) {
      throw const MarketDataException(
          'تجاوز التاريخ المحمّل حد الذاكرة. أعد فتح الشارت.');
    }
    if (appended.isEmpty) {
      // All returned provider bars matched verified CLOSED history. Preserve
      // the existing list identity: a poll with zero new closes must not
      // copy 100k+ candles into a fresh unmodifiable list.
      // Every overlap, gap and history limit has already been verified above.
      return existing;
    }
    return List<MarketBar>.unmodifiable([...existing, ...appended]);
  }
}
