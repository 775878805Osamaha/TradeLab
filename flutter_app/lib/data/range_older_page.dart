import 'market_api.dart';

/// Plans one backward Range page and checks it against the requested
/// *inclusive* interval. A cTrader call must use these exact bounds, not the
/// six-day convenience request used to initialize older legacy charts.
class RangeOlderPage {
  static const lookback = Duration(hours: 12);
  static const maxLoadedTicks = 1000000;

  static ({int fromMs, int toMs}) bounds(int endMs) {
    if (endMs < lookback.inMilliseconds) {
      throw RangeError.value(endMs, 'endMs', 'Insufficient history');
    }
    return (fromMs: endMs - lookback.inMilliseconds, toMs: endMs);
  }

  /// Both a signed cTrader response and an SHA-verified SQLite cache read
  /// must obey these same bounds. Do not trim or silently deduplicate.
  static List<MarketTick> verify({
    required List<MarketTick> page,
    required int fromMs,
    required int toMs,
    required int alreadyLoaded,
  }) {
    if (fromMs < 0 || toMs < fromMs ||
        toMs - fromMs != lookback.inMilliseconds ||
        alreadyLoaded < 0 || alreadyLoaded > maxLoadedTicks) {
      throw ArgumentError('Invalid older Range page bounds');
    }
    if (page.length > maxLoadedTicks - alreadyLoaded) {
      throw const MarketDataException(
          'عدد تيكات المدى يتجاوز الحد الآمن للذاكرة. '
          'حمّل تاريخًا أقصر قبل متابعة التمرير.');
    }
    var previous = fromMs;
    for (final tick in page) {
      if (tick.timestamp < previous || tick.timestamp > toMs ||
          !tick.bid.isFinite || tick.bid <= 0) {
        throw const MarketDataException(
            'تيكات صفحة المدى الأقدم لا تطابق الفترة الزمنية الموثقة.');
      }
      previous = tick.timestamp;
    }
    return page;
  }
}
