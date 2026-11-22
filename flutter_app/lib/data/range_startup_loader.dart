import 'market_api.dart';
import 'range_bar_timeline.dart';
import 'range_bid_page_verifier.dart';

/// A contiguous, source-verified set of BID ticks used to draw Range bars.
/// The loader requests short, disjoint intervals newest first. It never
/// derives ticks from OHLC, fills gaps, or accepts incomplete gateway pages.
class RangeStartupSnapshot {
  const RangeStartupSnapshot(this.fromMs, this.toMs, this.ticks, this.timeline);

  final int fromMs;
  final int toMs;
  final List<MarketTick> ticks;
  final RangeBarTimeline timeline;

  int get closedBars => timeline.bars.isEmpty ? 0 : timeline.bars.length - 1;
}

class RangeStartupLoader {
  // Cumulative UTC lookback horizons. During weekends or holidays a
  // 24h -> 3d jump used to fetch an entire 48-hour BID interval in one
  // provider call. Gold/XAUUSD can have a dense Friday in that interval,
  // forcing hundreds of disjoint cTrader pages before the first Range
  // candle is shown. Split older coverage into <=12h authenticated slices
  // after the first day; publish the FIRST complete window containing
  // actual BID ticks without downloading the whole weekend+Friday block.
  //
  // Every interval remains exact, inclusive, disjoint and verified. This is
  // not a market-hours calendar: closed-market intervals must be confirmed
  // empty by the broker and NO missing or fictional ticks are inserted.
  static const horizons = <Duration>[
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
    Duration(hours: 4),
    Duration(hours: 12),
    Duration(hours: 24),
    Duration(hours: 36),
    Duration(hours: 48),
    Duration(hours: 60),
    Duration(hours: 72),
    Duration(hours: 84),
    Duration(hours: 96),
    Duration(hours: 108),
    Duration(hours: 120),
    Duration(hours: 132),
    Duration(hours: 144),
  ];
  static const maxStartupTicks = 1000000;

  /// [getTicks] must return an ordered, complete and verified cTrader BID
  /// response for the *inclusive* requested interval. Adjacent windows never
  /// overlap, even when the broker has multiple ticks at one millisecond.
  static Future<RangeStartupSnapshot?> load({
    required int endMs,
    required double priceDistance,
    required Future<List<MarketTick>> Function(int fromMs, int toMs) getTicks,
    required Future<void> Function(RangeStartupSnapshot) onSnapshot,
    // A broker window may be persisted only after strict BID validation.
    // This callback also receives authenticated quiet (empty) windows.
    void Function(int fromMs, int toMs, List<MarketTick> ticks)?
        onVerifiedPage,
    // A history request can be superseded while a large BID page is being
    // verified on another isolate; never publish or archive stale results.
    bool Function()? isCurrent,
    int minimumClosedBars = 12,
  }) async {
    if (endMs <= horizons.last.inMilliseconds ||
        !priceDistance.isFinite || priceDistance <= 0 ||
        minimumClosedBars < 1) {
      throw ArgumentError('Invalid Range startup bounds');
    }

    var priorFrom = endMs + 1;
    var combined = <MarketTick>[];
    RangeStartupSnapshot? latest;
    int? lastNotifiedFromMs;
    for (final horizon in horizons) {
      if (isCurrent != null && !isCurrent()) return null;
      final fromMs = endMs - horizon.inMilliseconds;
      final toMs = priorFrom - 1;
      final page = await getTicks(fromMs, toMs);
      if (isCurrent != null && !isCurrent()) return null;
      // Reject oversized provider pages BEFORE spawning an isolate and
      // duplicating up to a million BID objects across worker boundaries.
      // Failed pages must never be certified as complete local coverage.
      if (page.length > maxStartupTicks - combined.length) {
        throw const MarketDataException(
            'تاريخ cTrader أكبر من الحد الآمن للذاكرة. '
            'اختر مدى أكبر أو حدّث بيانات الوسيط.');
      }
      // An authenticated 12-hour cTrader interval can contain 100k+ BID
      // events. Verify exact bounds/order off the UI isolate before any
      // snapshot or persistent cache publication; preserve same-ms ticks.
      await RangeBidPageVerifier.verifyAsync(
        page: page,
        fromMs: fromMs,
        toMs: toMs,
        errorMessage:
            'تيكات cTrader لا تتوافق مع النوافذ الزمنية المطلوبة.',
      );
      if (isCurrent != null && !isCurrent()) return null;
      // Do not certify a window until it is fully validated, below the
      // memory cap and still belongs to this account/symbol/revision.
      onVerifiedPage?.call(fromMs, toMs, page);
      priorFrom = fromMs;
      if (page.isEmpty) {
        // This is a broker-verified quiet interval, not a missing interval.
        // Extend the known coverage cursor without copying all cached BID
        // events or recomputing exactly the same Range timeline.
        if (latest != null) {
          latest = RangeStartupSnapshot(
              fromMs, endMs, latest.ticks, latest.timeline);
        }
        continue;
      }
      // Build one immutable source archive and the corresponding Range
      // timeline together. Large pages are merged AND rebuilt in a compute
      // isolate, rather than copying up to 1m BID events on the UI isolate
      // before handing the work to another isolate. Published snapshots
      // remain immutable while verified older windows are prepended.
      final rebuilt = await RangeBarTimeline.prependAndBuildAsync(
        olderTicks: page,
        currentTicks: combined,
        priceDistance: priceDistance,
      );
      if (isCurrent != null && !isCurrent()) return null;
      combined = rebuilt.ticks;
      latest = RangeStartupSnapshot(
          fromMs, endMs, combined, rebuilt.timeline);
      await onSnapshot(latest);
      if (isCurrent != null && !isCurrent()) return null;
      lastNotifiedFromMs = fromMs;
      if (latest.closedBars >= minimumClosedBars) break;
    }
    // Commit final verified coverage even if the last older windows were
    // quiet. Older paging must not request already-verified closed periods.
    if (isCurrent != null && !isCurrent()) return null;
    if (latest != null && latest.fromMs != lastNotifiedFromMs) {
      await onSnapshot(latest);
    }
    return latest;
  }
}
