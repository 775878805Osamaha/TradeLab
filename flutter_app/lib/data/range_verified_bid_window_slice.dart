import 'market_api.dart';

/// Extracts only the requested inclusive interval from a verified,
/// chronologically ordered broker BID window.
///
/// The caller must first validate the full window's SHA-256 manifest and
/// source tick order (RangeTickStore.readVerifiedWindow). This deliberately
/// does not "repair" or infer missing data. Equal-millisecond BID events
/// remain distinct; both bounds are inclusive. When only a tiny portion of
/// a 100k+ cached window overlaps a chart request, searching source indexes
/// is logarithmic instead of scanning every cached tick on Flutter's UI
/// isolate.
abstract final class RangeVerifiedBidWindowSlice {
  /// Appends only [fromMs, toMs] events from a complete trusted window.
  ///
  /// Returns false without changing [output] if the result would exceed
  /// [maxTicks]. This enforces the memory budget BEFORE copying any ticks.
  static bool appendWithinLimit({
    required List<MarketTick> verified,
    required int fromMs,
    required int toMs,
    required List<MarketTick> output,
    required int maxTicks,
  }) {
    if (fromMs < 0 || toMs < fromMs ||
        maxTicks < 1 || output.length > maxTicks) {
      throw ArgumentError('Invalid verified BID window slice bounds');
    }

    // Lower bound: first event with timestamp >= inclusive start.
    var lo = 0;
    var hi = verified.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (verified[mid].timestamp < fromMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final start = lo;

    // Upper bound: first event with timestamp > inclusive end. Start
    // searching at the lower bound so empty/quiet slices stay cheap.
    lo = start;
    hi = verified.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (verified[mid].timestamp <= toMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final end = lo;

    if (end - start > maxTicks - output.length) return false;
    for (var i = start; i < end; i++) {
      output.add(verified[i]);
    }
    return true;
  }
}
