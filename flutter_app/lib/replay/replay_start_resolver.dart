import '../chart/chart_viewport.dart';

/// Maps Replay's draggable cursor to a real loaded bar and broker timestamp.
/// It never interpolates ticks, creates candles or fabricates timestamps.
class ReplayStartResolver {
  const ReplayStartResolver._();

  static bool hasVerifiedTimes(List<int> timestamps, int completedCount) {
    if (completedCount < 2 || timestamps.length < completedCount) return false;
    var previous = -1;
    for (var i = 0; i < completedCount; i++) {
      final time = timestamps[i];
      if (time <= 0 || time < previous) return false;
      previous = time;
    }
    return true;
  }

  /// The final completed bar cannot be a useful start: no forward step exists.
  static int maxStart(int completedCount) => completedCount < 2
      ? 0 : completedCount - 2;

  static int atX({
    required ChartViewport viewport,
    required double x,
    required double plotWidth,
    required int candleCount,
    required int completedCount,
    required int fallbackIndex,
  }) {
    final index = viewport.indexAt(
      x: x, plotWidth: plotWidth, candleCount: candleCount);
    return (index ?? fallbackIndex).clamp(0, maxStart(completedCount)).toInt();
  }

  /// Returns the latest loaded completed bar at/before a local timestamp
  /// converted by the caller to UTC milliseconds. -1 means no such bar.
  /// Holidays and broker gaps are resolved to an existing earlier candle.
  static int atOrBefore(
      List<int> timestamps, int completedCount, int requestedUtcMs) {
    if (!hasVerifiedTimes(timestamps, completedCount) ||
        requestedUtcMs < timestamps.first) return -1;
    var lo = 0;
    var hi = completedCount;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (timestamps[mid] <= requestedUtcMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (lo - 1).clamp(0, maxStart(completedCount)).toInt();
  }

  static int timestampAt(List<int> timestamps, int index,
      int completedCount) {
    if (!hasVerifiedTimes(timestamps, completedCount) ||
        index < 0 || index >= completedCount) {
      throw StateError('Replay start has no verified market timestamp.');
    }
    return timestamps[index];
  }
}


/// One verified, immutable market timestamp source for Replay actions.
///
/// Validate the currently published provider snapshot once per list identity
/// and completed candle count, then perform repeated time-picker seeks in
/// O(log N). Without this bounded cache, the legacy static atOrBefore and
/// timestampAt helpers each scanned the entire 120k/200k source archive
/// again before doing their actual constant/logarithmic work.
///
/// CONTRACT: the chart publishes a NEW timestamp list when the source data
/// changes; it must never mutate a published list in place. Range source
/// events are allowed to share UTC milliseconds. The final forming Range
/// bar remains excluded through [completedCount].
///
/// The stateless ReplayStartResolver methods above remain strict for callers
/// that do not own an immutable, source-verified snapshot.
class ReplayVerifiedTimeIndex {
  List<int>? _source;
  int? _completedCount;
  bool _valid = false;

  bool hasVerifiedTimes(List<int> timestamps, int completedCount) {
    if (!identical(_source, timestamps) ||
        _completedCount != completedCount) {
      _source = timestamps;
      _completedCount = completedCount;
      _valid = ReplayStartResolver.hasVerifiedTimes(
          timestamps, completedCount);
    }
    return _valid;
  }

  int atOrBefore(
      List<int> timestamps, int completedCount, int requestedUtcMs) {
    if (!hasVerifiedTimes(timestamps, completedCount) ||
        requestedUtcMs < timestamps.first) {
      return -1;
    }
    var lo = 0;
    var hi = completedCount;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (timestamps[mid] <= requestedUtcMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // A valid start must leave at least one confirmed future bar for Replay.
    return (lo - 1).clamp(0,
        ReplayStartResolver.maxStart(completedCount)).toInt();
  }

  int timestampAt(List<int> timestamps, int index, int completedCount) {
    if (!hasVerifiedTimes(timestamps, completedCount) ||
        index < 0 || index >= completedCount) {
      throw StateError('Replay start has no verified market timestamp.');
    }
    return timestamps[index];
  }

  void clear() {
    _source = null;
    _completedCount = null;
    _valid = false;
  }
}

/// An async Replay date/time picker can remain open while the account,
/// market, history revision, timezone or selection session changes.
/// The chosen UTC instant is meaningful ONLY for the original verified
/// source. Discard its stale result instead of seeking the same index in
/// another symbol's candles or revealing a future candle by accident.
class ReplayDateSelectionGuard {
  const ReplayDateSelectionGuard({
    required this.timestamps,
    required this.completedCount,
    required this.loadRevision,
    required this.symbol,
    required this.timeframe,
    required this.provider,
    required this.accountId,
    required this.zoneKey,
    required this.selectionEpoch,
  });

  final List<int> timestamps;
  final int completedCount;
  final int loadRevision;
  final String symbol;
  final String timeframe;
  final String provider;
  final String? accountId;
  final String zoneKey;
  // Each new in-chart start selection gets a distinct epoch even if the
  // broker, symbol and immutable candle archive are unchanged.
  final int selectionEpoch;

  bool isCurrent({
    required List<int> timestamps,
    required int completedCount,
    required int loadRevision,
    required String symbol,
    required String timeframe,
    required String provider,
    required String? accountId,
    required String zoneKey,
    required int selectionEpoch,
    required bool selectingStart,
  }) => selectingStart &&
      this.selectionEpoch == selectionEpoch &&
      identical(this.timestamps, timestamps) &&
      this.completedCount == completedCount &&
      this.loadRevision == loadRevision &&
      this.symbol == symbol &&
      this.timeframe == timeframe &&
      this.provider == provider &&
      this.accountId == accountId &&
      this.zoneKey == zoneKey;
}


/// Captures the complete identity of an in-chart Replay session while an
/// asynchronous dialog is open. A modal may outlive an account switch,
/// market reload, Range-size change or a new training session. The same
/// last-revealed price/index is NOT proof that the old action is still valid.
///
/// Source data is compared by immutable list identity, not by scanning a
/// 200k-bar timestamp archive on the Flutter UI isolate.
class ReplayAsyncSessionGuard {
  const ReplayAsyncSessionGuard({
    required this.timestamps,
    required this.completedCount,
    required this.loadRevision,
    required this.symbol,
    required this.timeframe,
    required this.provider,
    required this.accountId,
    required this.chartMode,
    required this.trainingSessionId,
    required this.replayActive,
    required this.selectingStart,
  });

  final List<int> timestamps;
  final int completedCount;
  final int loadRevision;
  final String symbol;
  final String timeframe;
  final String provider;
  final String? accountId;
  final String chartMode;
  final String trainingSessionId;
  final bool replayActive;
  final bool selectingStart;

  bool isCurrent({
    required List<int> timestamps,
    required int completedCount,
    required int loadRevision,
    required String symbol,
    required String timeframe,
    required String provider,
    required String? accountId,
    required String chartMode,
    required String trainingSessionId,
    required bool replayActive,
    required bool selectingStart,
  }) =>
      identical(this.timestamps, timestamps) &&
      this.completedCount == completedCount &&
      this.loadRevision == loadRevision &&
      this.symbol == symbol &&
      this.timeframe == timeframe &&
      this.provider == provider &&
      this.accountId == accountId &&
      this.chartMode == chartMode &&
      this.trainingSessionId == trainingSessionId &&
      this.replayActive == replayActive &&
      this.selectingStart == selectingStart;
}
