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
