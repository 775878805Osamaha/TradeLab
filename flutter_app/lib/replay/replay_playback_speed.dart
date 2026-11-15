/// Explicit Replay speeds. Every tick reveals ONE verified historical bar;
/// playback speed never changes market data or reveals a future candle.
enum ReplayPlaybackSpeed {
  half('0.5×', 1300),
  normal('1×', 650),
  twice('2×', 325),
  fourTimes('4×', 163),
  eightTimes('8×', 82);

  const ReplayPlaybackSpeed(this.label, this.intervalMs);
  final String label;
  final int intervalMs;
  Duration get interval => Duration(milliseconds: intervalMs);
}
