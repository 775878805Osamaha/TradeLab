import 'market_api.dart';
import 'range_bid_page_verifier.dart';

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

  /// The scanner has already authenticated and validated source ordering
  /// and the exact inclusive 12-hour window. A single last-tick comparison
  /// proves that ALL older ticks precede the currently displayed earliest
  /// BID event. Do not scan 120k+ ticks again on the Flutter gesture isolate.
  ///
  /// Equality is an overlap: different broker events can share a timestamp,
  /// so an overlapping millisecond cannot be silently spliced or deduplicated.
  /// Call only after verify/verifyAsync succeeded for this page.
  static bool overlapsLoadedHistory({
    required List<MarketTick> sortedVerifiedOlder,
    required int earliestLoadedMs,
  }) =>
      sortedVerifiedOlder.isNotEmpty &&
      sortedVerifiedOlder.last.timestamp >= earliestLoadedMs;

  /// Both a signed cTrader response and an SHA-verified SQLite cache read
  /// must obey these same bounds. Do not trim or silently deduplicate.
  static List<MarketTick> verify({
    required List<MarketTick> page,
    required int fromMs,
    required int toMs,
    required int alreadyLoaded,
  }) {
    _checkBounds(
      pageLength: page.length,
      fromMs: fromMs,
      toMs: toMs,
      alreadyLoaded: alreadyLoaded,
    );
    RangeBidPageVerifier.verify(
      page: page,
      fromMs: fromMs,
      toMs: toMs,
      errorMessage:
          'تيكات صفحة المدى الأقدم لا تطابق الفترة الزمنية الموثقة.',
    );
    return page;
  }

  /// A large authenticated BID page must not block drawing gestures while
  /// validating every source tick. Retain the exact original page instance;
  /// no sorting, deduplication or artificial continuity is introduced.
  static Future<List<MarketTick>> verifyAsync({
    required List<MarketTick> page,
    required int fromMs,
    required int toMs,
    required int alreadyLoaded,
  }) async {
    _checkBounds(
      pageLength: page.length,
      fromMs: fromMs,
      toMs: toMs,
      alreadyLoaded: alreadyLoaded,
    );
    await RangeBidPageVerifier.verifyAsync(
      page: page,
      fromMs: fromMs,
      toMs: toMs,
      errorMessage:
          'تيكات صفحة المدى الأقدم لا تطابق الفترة الزمنية الموثقة.',
    );
    return page;
  }

  static void _checkBounds({
    required int pageLength,
    required int fromMs,
    required int toMs,
    required int alreadyLoaded,
  }) {
    if (fromMs < 0 || toMs < fromMs ||
        toMs - fromMs != lookback.inMilliseconds ||
        alreadyLoaded < 0 || alreadyLoaded > maxLoadedTicks) {
      throw ArgumentError('Invalid older Range page bounds');
    }
    if (pageLength > maxLoadedTicks - alreadyLoaded) {
      throw const MarketDataException(
          'عدد تيكات المدى يتجاوز الحد الآمن للذاكرة. '
          'حمّل تاريخًا أقصر قبل متابعة التمرير.');
    }
  }
}
