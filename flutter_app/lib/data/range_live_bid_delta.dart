import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'market_api.dart';
import 'range_bid_page_verifier.dart';

/// Authenticated, complete cTrader BID response for [lastTickMs..nowMs].
///
/// The latest already-loaded broker millisecond can contain several distinct
/// events. An EXCLUSIVE time request would silently discard newer events
/// whose millisecond is equal to the last loaded timestamp. Query the same
/// millisecond inclusively instead and demand that the entire old same-ms
/// tail appears as an EXACT, ORDERED prefix of the new signed page.
///
/// This does not infer sequence from prices or deduplicate equal-price ticks:
/// the provider's original event ordinal is the authority. A missing/revised
/// prefix fails closed rather than quietly corrupting Range Replay indices.
class RangeLiveBidDelta {
  const RangeLiveBidDelta._();

  static Future<List<MarketTick>> verifiedSuffixAsync({
    required List<MarketTick> previouslyVerified,
    required List<MarketTick> brokerPage,
    required int toMs,
  }) async {
    if (previouslyVerified.isEmpty) {
      throw ArgumentError('Live BID update requires a verified Range source');
    }
    final fromMs = previouslyVerified.last.timestamp;
    await RangeBidPageVerifier.verifyAsync(
      page: brokerPage,
      fromMs: fromMs,
      toMs: toMs,
      errorMessage:
          'صفحة التحديث الحي لتيكات BID غير مرتبة أو خارج فترة cTrader.',
    );
    if (brokerPage.isEmpty) {
      // Even an otherwise quiet interval must include the authenticated
      // already-loaded last millisecond when fetched INCLUSIVELY.
      throw const MarketDataException(
          'لم يتطابق آخر تيك BID موثق مع صفحة التحديث الحي.');
    }
    final request = (previouslyVerified, brokerPage, fromMs);
    if (!kIsWeb && brokerPage.length >= 5000) {
      return compute<(List<MarketTick>, List<MarketTick>, int),
          List<MarketTick>>(
        _verifiedLiveSuffixWorker, request,
        debugLabel: 'tradelab-live-bid-overlap',
      );
    }
    return _verifiedLiveSuffixWorker(request);
  }

  static List<MarketTick> _verifiedLiveSuffixWorker(
      (List<MarketTick>, List<MarketTick>, int) request) {
    final previous = request.$1;
    final fetched = request.$2;
    final boundaryMs = request.$3;
    // Timestamp-sorted authenticated archive. Find its exact duplicate
    // suffix via lower-bound in O(log N) even for 1m original BID events.
    var low = 0;
    var high = previous.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (previous[mid].timestamp < boundaryMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final oldBoundaryCount = previous.length - low;
    if (oldBoundaryCount > fetched.length) {
      throw const MarketDataException(
          'صفحة BID الجديدة لا تحتوي كل الأحداث القديمة من نفس المللي ثانية.');
    }
    for (var i = 0; i < oldBoundaryCount; i++) {
      final earlier = previous[low + i];
      final newer = fetched[i];
      if (earlier.timestamp != newer.timestamp ||
          earlier.bid != newer.bid) {
        throw const MarketDataException(
            'تعارض ترتيب أو سعر تيكات BID عند حد تحديث Range.');
      }
    }
    if (oldBoundaryCount == fetched.length) {
      return const <MarketTick>[];
    }
    return List<MarketTick>.unmodifiable(
        fetched.skip(oldBoundaryCount));
  }
}
