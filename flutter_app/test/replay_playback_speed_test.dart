import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/replay/replay_playback_speed.dart';

void main() {
  test('Replay speed menu exposes accurate 0.25x through 10x ratios', () {
    final speeds = ReplayPlaybackSpeed.values;
    expect(speeds.map((speed) => speed.label).toList(), [
      '0.25×', '0.5×', '1×', '2×', '5×', '10×',
    ]);
    expect(speeds.map((speed) => speed.intervalMs).toList(), [
      2600, 1300, 650, 325, 130, 65,
    ]);
    for (final speed in speeds) {
      expect(speed.interval.inMilliseconds, speed.intervalMs);
      expect(speed.intervalMs, greaterThanOrEqualTo(60),
          reason: 'Throttle Replay updates to protect mobile drawing budget');
    }
  });
}
