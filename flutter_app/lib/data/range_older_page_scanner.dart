import 'market_api.dart';
import 'range_older_page.dart';

/// A bounded historical BID search result. All checked windows are complete,
/// exact inclusive cTrader intervals or digest-verified local equivalents.
/// [nextCursorMs] is an exclusive cursor for the next older request.
class RangeOlderScanResult {
  const RangeOlderScanResult({
    required this.ticks,
    required this.fromMs,
    required this.toMs,
    required this.nextCursorMs,
    required this.emptyWindows,
  });

  final List<MarketTick> ticks;
  final int fromMs;
  final int toMs;
  final int nextCursorMs;
  final int emptyWindows;
}

/// Searches past broker-verified quiet BID windows without inventing Range
/// candles or repeatedly requiring another gesture after a market holiday.
///
/// The provider callback must fetch the EXACT requested inclusive interval
/// and verify completeness; scanner independently validates each page.
/// The search is strictly capped, and all periods remain nonoverlapping.
class RangeOlderPageScanner {
  const RangeOlderPageScanner._();

  static const maxQuietWindowsPerAttempt = 6;

  static Future<RangeOlderScanResult?> scan({
    required int cursorMs,
    required int alreadyLoaded,
    required Future<List<MarketTick>> Function(int fromMs, int toMs)
        fetchVerified,
    required bool Function() isCurrent,
    int maxPages = maxQuietWindowsPerAttempt,
  }) async {
    if (cursorMs < 0 || alreadyLoaded < 0 ||
        alreadyLoaded > RangeOlderPage.maxLoadedTicks ||
        maxPages < 1 || maxPages > maxQuietWindowsPerAttempt) {
      throw ArgumentError('Invalid bounded Range BID page scan');
    }
    var cursor = cursorMs;
    var emptyWindows = 0;
    var lastFromMs = 0;
    var lastToMs = 0;
    for (var page = 0; page < maxPages; page++) {
      if (!isCurrent()) return null;
      if (cursor < RangeOlderPage.lookback.inMilliseconds) break;

      final bounds = RangeOlderPage.bounds(cursor);
      lastFromMs = bounds.fromMs;
      lastToMs = bounds.toMs;
      final ticks = await fetchVerified(bounds.fromMs, bounds.toMs);
      if (!isCurrent()) return null;
      RangeOlderPage.verify(
        page: ticks, fromMs: bounds.fromMs, toMs: bounds.toMs,
        alreadyLoaded: alreadyLoaded,
      );
      final next = bounds.fromMs > 0 ? bounds.fromMs - 1 : 0;
      if (ticks.isNotEmpty) {
        return RangeOlderScanResult(
          ticks: ticks, fromMs: bounds.fromMs, toMs: bounds.toMs,
          nextCursorMs: next, emptyWindows: emptyWindows,
        );
      }
      emptyWindows++;
      cursor = next;
      if (cursor == 0) break;
    }
    return RangeOlderScanResult(
      ticks: const <MarketTick>[], fromMs: lastFromMs, toMs: lastToMs,
      nextCursorMs: cursor, emptyWindows: emptyWindows,
    );
  }
}
