import 'package:flutter/foundation.dart' show compute, kIsWeb;

import 'market_api.dart';
import 'range_bid_page_verifier.dart';

/// Immutable proof of the **last market millisecond only**, never a second
/// copy of the entire 1,000,000-tick Range history.
///
/// A cTrader inclusive poll only needs the original ordered events from its
/// overlap millisecond to distinguish new same-ms BID events from history.
/// Source snapshots are already broker-verified and never mutated in place.
/// The oldest tick is found by binary search; on a normal quiet market this
/// transfers 1 or 2 events, not the 1m-source list, to the worker isolate.
class RangeLiveBidBoundary {
  RangeLiveBidBoundary._(this.timestampMs, this.events);

  /// Match the hard cap enforced by RangeBarTimeline on Android and web.
  /// Reject impossible archives before even touching an unmaterialized list.
  static const maxVerifiedSourceTicks = 1000000;

  final int timestampMs;
  final List<MarketTick> events;

  static RangeLiveBidBoundary fromVerified(List<MarketTick> ticks) {
    if (ticks.length > maxVerifiedSourceTicks) {
      throw const MarketDataException(
          'تاريخ BID المحمّل تجاوز حد الذاكرة الآمن لتحديث Range.');
    }
    if (ticks.isEmpty) {
      throw ArgumentError('Live BID update requires a verified Range source');
    }
    final timestamp = ticks.last.timestamp;
    if (timestamp < 0 || !ticks.last.bid.isFinite ||
        ticks.last.bid <= 0) {
      throw const MarketDataException(
          'آخر حدث BID المؤرّخ من المصدر غير صالح.');
    }
    var low = 0;
    var high = ticks.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (ticks[mid].timestamp < timestamp) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low == ticks.length) {
      throw const MarketDataException('لا توجد أحداث BID في حد المصدر.');
    }
    final tail = <MarketTick>[];
    for (var i = low; i < ticks.length; i++) {
      final event = ticks[i];
      if (event.timestamp != timestamp ||
          !event.bid.isFinite || event.bid <= 0) {
        throw const MarketDataException(
            'ترتيب أحداث BID الأخيرة في الأرشيف غير صالح.');
      }
      tail.add(event);
    }
    return RangeLiveBidBoundary._(
        timestamp, List<MarketTick>.unmodifiable(tail));
  }
}

/// Authenticated inclusive cTrader BID update from [lastTickMs..nowMs].
///
/// The old same-millisecond events MUST appear as an exact, ordered prefix.
/// Same-price duplicates are retained, source conflicts fail closed, and
/// only the final-ms boundary (not the entire verified historical archive)
/// is sent to the comparison worker for large broker pages.
class RangeLiveBidDelta {
  const RangeLiveBidDelta._();

  static Future<List<MarketTick>> verifiedSuffixAsync({
    required List<MarketTick> previouslyVerified,
    required List<MarketTick> brokerPage,
    required int toMs,
  }) async {
    // Capture only the final same-ms events on the UI isolate. The earlier
    // implementation sent ALL previouslyVerified (up to 1m ticks) to the
    // compute worker even though the comparison only reads the last ms.
    final boundary = RangeLiveBidBoundary.fromVerified(previouslyVerified);
    final fromMs = boundary.timestampMs;
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
    // The large broker page still has to be verified in full, but the old
    // account-scoped archive is no longer transferred to a second isolate.
    final request = (boundary.events, brokerPage, fromMs);
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
    // The input is now an isolated, immutable final-ms boundary captured
    // with O(log N + same-ms-event-count) source reads before the async call.
    // Every event (including identical price/timestamp duplicates) remains
    // necessary to preserve the original provider ordinal for Replay.
    final oldBoundaryCount = previous.length;
    if (oldBoundaryCount > fetched.length) {
      throw const MarketDataException(
          'صفحة BID الجديدة لا تحتوي كل الأحداث القديمة من نفس المللي ثانية.');
    }
    for (var i = 0; i < oldBoundaryCount; i++) {
      final earlier = previous[i];
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
