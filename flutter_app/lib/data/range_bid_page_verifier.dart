import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'market_api.dart';

/// Strict page-bound cTrader BID verification, shared by initial Range
/// startup and backward Range history. Sorting, rounding or deduplicating
/// source ticks here would corrupt same-millisecond BID Replay boundaries.
///
/// Large broker/cache pages are verified off the Android UI isolate. The
/// worker returns only a flag: the original page is never copied back and
/// can be published or archived only after verification has completed.
class RangeBidPageVerifier {
  const RangeBidPageVerifier._();

  static const minOffloadTicks = 5000;

  static bool shouldOffload(int tickCount) =>
      !kIsWeb && tickCount >= minOffloadTicks;

  static void verify({
    required List<MarketTick> page,
    required int fromMs,
    required int toMs,
    required String errorMessage,
  }) {
    if (fromMs < 0 || toMs < fromMs) {
      throw ArgumentError('Invalid inclusive BID page bounds');
    }
    var previous = fromMs;
    for (final tick in page) {
      if (tick.timestamp < previous || tick.timestamp > toMs ||
          !tick.bid.isFinite || tick.bid <= 0) {
        throw MarketDataException(errorMessage);
      }
      previous = tick.timestamp;
    }
  }

  static Future<void> verifyAsync({
    required List<MarketTick> page,
    required int fromMs,
    required int toMs,
    required String errorMessage,
  }) async {
    if (fromMs < 0 || toMs < fromMs) {
      throw ArgumentError('Invalid inclusive BID page bounds');
    }
    if (!shouldOffload(page.length)) {
      verify(
        page: page, fromMs: fromMs, toMs: toMs,
        errorMessage: errorMessage);
      return;
    }
    await compute<
        (List<MarketTick>, int, int, String),
        bool>(
      _verifyBidPageWorker,
      (page, fromMs, toMs, errorMessage),
      debugLabel: 'tradelab-verified-range-bid-page',
    );
  }
}

bool _verifyBidPageWorker(
    (List<MarketTick>, int, int, String) request) {
  RangeBidPageVerifier.verify(
    page: request.$1,
    fromMs: request.$2,
    toMs: request.$3,
    errorMessage: request.$4,
  );
  return true;
}
