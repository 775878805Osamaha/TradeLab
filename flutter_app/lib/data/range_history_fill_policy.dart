import 'dart:math' as math;

/// A bounded, user-facing goal for genuine cTrader BID Range backfill.
/// Reaching a target means only "enough closed bars to browse", NEVER
/// claiming the broker's entire historical archive has been downloaded.
class RangeHistoryFillPolicy {
  const RangeHistoryFillPolicy._();

  // Limit background requests and memory; edge panning can request older
  // independent verified BID windows after this first bounded pass.
  static const maxAutomaticOlderPages = 24;
  static const minVisibleClosedBars = 48;
  static const maxVisibleClosedBars = 128;

  static int targetClosedBars({
    required double plotWidth,
    required double candleWidth,
  }) {
    if (!plotWidth.isFinite || plotWidth <= 0 ||
        !candleWidth.isFinite || candleWidth <= 0) {
      return minVisibleClosedBars;
    }
    // Fill the visible viewport plus some history for smooth browsing.
    // This is independent of Range points and never manufactures BID ticks.
    final wanted = (plotWidth / candleWidth).ceil() + 24;
    return math.max(minVisibleClosedBars,
        math.min(maxVisibleClosedBars, wanted));
  }

  static bool shouldContinue({
    required int completedPages,
    required int closedBars,
    required int targetBars,
    required int loadedTicks,
    required bool authenticatedSource,
    required bool chartActive,
    required bool historicalReplay,
    required bool loading,
    required bool historyExhausted,
    required bool sourceError,
  }) =>
      completedPages >= 0 &&
      completedPages < maxAutomaticOlderPages &&
      closedBars < targetBars &&
      loadedTicks > 0 && loadedTicks < 1000000 &&
      authenticatedSource && chartActive &&
      !historicalReplay && !loading && !historyExhausted && !sourceError;
}

/// Prevents an older, still-pending broker request from blocking the
/// current symbol/account's Range backfill or clearing the NEW run's flag.
///
/// ChartScreen increments its load revision whenever the symbol, account,
/// timeframe or Range mode is replaced. It owns the cancellation decision;
/// this tiny gate only makes the in-flight status generation-aware.
class RangeAutoFillRevisionGate {
  int? _revision;

  bool isActiveFor(int revision) => _revision == revision;

  bool start(int revision) {
    if (revision < 0 || _revision == revision) return false;
    _revision = revision;
    return true;
  }

  void finish(int revision) {
    if (_revision == revision) _revision = null;
  }
}
