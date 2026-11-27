/// Replay playback speed changes only elapsed time between revealing REAL
/// source-verified bars; it must never skip or synthesize OHLC / tick data.
///
/// 1x is intentionally 650ms per completed bar to preserve the existing
/// app pacing. All other speeds are exact ratios of this base interval.
enum ReplayPlaybackSpeed {
  quarter('0.25×', 2600),
  half('0.5×', 1300),
  normal('1×', 650),
  twice('2×', 325),
  fiveTimes('5×', 130),
  tenTimes('10×', 65);

  const ReplayPlaybackSpeed(this.label, this.intervalMs);
  final String label;
  final int intervalMs;
  Duration get interval => Duration(milliseconds: intervalMs);
}
