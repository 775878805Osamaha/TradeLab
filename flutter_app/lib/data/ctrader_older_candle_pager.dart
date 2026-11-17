import 'tradelab_data.dart';

/// Result of a bounded search for older, broker-verified cTrader OHLC bars.
///
/// [nextCursorMs] is the exclusive upper cursor to use if no bar was found.
/// Quiet windows do not create candles, and their coverage is not inferred
/// from neighboring bar timestamps.
class CTraderOlderCandlePage {
  const CTraderOlderCandlePage({
    required this.bars,
    required this.nextCursorMs,
    required this.quietWindows,
  });

  final List<MarketBar> bars;
  final int nextCursorMs;
  final int quietWindows;
}

/// Skip a bounded number of genuinely empty cTrader history windows in one
/// user-initiated or edge-prefetch request. Before this, each quiet window
/// stopped loading and required another tap on «أقدم».
///
/// Every remote page is requested with an exclusive upper timestamp. This
/// helper neither fabricates bars nor changes Replay's visible prefix.
class CTraderOlderCandlePager {
  CTraderOlderCandlePager._();

  static const maxQuietWindowsPerAttempt = 5;

  static Future<CTraderOlderCandlePage?> load({
    required int cursorMs,
    required Duration lookback,
    required Future<List<MarketBar>> Function(DateTime before) fetch,
    required bool Function() isCurrent,
    int maxPages = maxQuietWindowsPerAttempt,
  }) async {
    if (cursorMs < 1 || lookback.inMilliseconds < 1 ||
        maxPages < 1 || maxPages > maxQuietWindowsPerAttempt) {
      throw ArgumentError('Invalid bounded cTrader history search');
    }

    var cursor = cursorMs;
    var quietWindows = 0;
    for (var page = 0; page < maxPages; page++) {
      // A new account, symbol or Replay session must not inherit stale data.
      if (!isCurrent()) return null;
      final beforeMs = cursor - 1;
      if (beforeMs < 1) break;
      final bars = await fetch(DateTime.fromMillisecondsSinceEpoch(
          beforeMs, isUtc: true));
      if (!isCurrent()) return null;
      if (bars.isNotEmpty) {
        return CTraderOlderCandlePage(
            bars: bars, nextCursorMs: cursor,
            quietWindows: quietWindows);
      }

      quietWindows++;
      // The query covers [before - lookback, before] inclusively. Resume
      // exactly one millisecond before that verified empty interval; do not
      // skip an unknown millisecond or request the same quiet window again.
      cursor = beforeMs - lookback.inMilliseconds;
      if (cursor < 1) {
        cursor = 0;
        break;
      }
    }
    return CTraderOlderCandlePage(
        bars: const <MarketBar>[], nextCursorMs: cursor,
        quietWindows: quietWindows);
  }
}
