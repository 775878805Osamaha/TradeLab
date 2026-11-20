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
    // Direct callers still validate the entire input archive. The chart's
    // already-verified refresh path below may avoid this 120k+ re-scan.
    return appendPreviouslyVerified(existing, recent);
  }

  /// Count new closed candles without allocating a replacement source array.
  /// PRECONDITION: [existing] is an immutable archive already validated by
  /// the authenticated cTrader feed or verified SQLite history.
  /// The small fresh broker response is *always* validated here.
  ///
  /// All overlaps use lower-bound search, so a no-change 30-second poll
  /// checks O(recent * log(existing.length)) rather than walking 120k bars.
  /// Historical gaps and revised OHLC are rejected before any publication.
  static int countNewFromVerifiedHistory(
      List<MarketBar> existing, List<MarketBar> recent) {
    validateBars(recent);
    if (existing.isEmpty) {
      if (recent.length > 200000) {
        throw const MarketDataException(
            'تجاوز التاريخ المحمّل حد الذاكرة. أعد فتح الشارت.');
      }
      return recent.length;
    }
    final latest = existing.last.timestamp;
    var appended = 0;
    for (final bar in recent) {
      if (bar.timestamp > latest) {
        appended++;
        continue;
      }
      var low = 0;
      var high = existing.length;
      while (low < high) {
        final mid = low + (high - low) ~/ 2;
        if (existing[mid].timestamp < bar.timestamp) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      if (low == existing.length ||
          existing[low].timestamp != bar.timestamp) {
        throw const MarketDataException(
            'تاريخ cTrader غير متصل؛ ظهرت شموع قديمة لم تُحمّل سابقًا.');
      }
      final prior = existing[low].candle;
      final incoming = bar.candle;
      if (prior.open != incoming.open ||
          prior.high != incoming.high ||
          prior.low != incoming.low ||
          prior.close != incoming.close) {
        throw const MarketDataException(
            'تغيّرت قيم شمعة cTrader تاريخية بين طلبين؛ '
            'أوقفنا التحديث حتى يُراجع المصدر.');
      }
    }
    if (existing.length + appended > 200000) {
      throw const MarketDataException(
          'تجاوز التاريخ المحمّل حد الذاكرة. أعد فتح الشارت.');
    }
    return appended;
  }

  /// The chart has already validated its stored history before publishing
  /// it. Preserve original object identity when all broker closes overlap.
  static List<MarketBar> appendPreviouslyVerified(
      List<MarketBar> existing, List<MarketBar> recent) {
    final appended = countNewFromVerifiedHistory(existing, recent);
    if (existing.isEmpty) return List<MarketBar>.unmodifiable(recent);
    if (appended == 0) return existing;
    return List<MarketBar>.unmodifiable([
      ...existing,
      ...recent.skip(recent.length - appended),
    ]);
  }
}
