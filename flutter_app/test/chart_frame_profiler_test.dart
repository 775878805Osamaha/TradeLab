import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_frame_profiler.dart';

void main() {
  test('frame time percentiles never invent samples', () {
    expect(ChartFrameProfiler.percentileUs([1000, 2000, 8000, 4000], .5),
        4000);
    expect(ChartFrameProfiler.percentileUs([1000, 2000, 8000, 4000], .95),
        8000);
    expect(() => ChartFrameProfiler.percentileUs([], .95),
        throwsArgumentError);
    expect(() => ChartFrameProfiler.percentileUs([10], 1.1),
        throwsArgumentError);
  });

  test('profiler is opt-in by default in test and release', () {
    expect(ChartFrameProfiler.enabled, isFalse);
  });
}
