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
  });

  final List<int> timestamps;
  final int completedCount;
  final int loadRevision;
  final String symbol;
  final String timeframe;
  final String provider;
  final String? accountId;
  final String zoneKey;

  bool isCurrent({
    required List<int> timestamps,
    required int completedCount,
    required int loadRevision,
    required String symbol,
    required String timeframe,
    required String provider,
    required String? accountId,
    required String zoneKey,
    required bool selectingStart,
  }) => selectingStart &&
      identical(this.timestamps, timestamps) &&
      this.completedCount == completedCount &&
      this.loadRevision == loadRevision &&
      this.symbol == symbol &&
      this.timeframe == timeframe &&
      this.provider == provider &&
      this.accountId == accountId &&
      this.zoneKey == zoneKey;
}
