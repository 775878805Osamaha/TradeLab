import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Optional real-device performance samples; disabled in all normal builds.
/// Enable only for a measured session with:
/// flutter run --profile --dart-define=TRADELAB_PROFILE_CHART=true
class ChartFrameProfiler {
  static const enabled = bool.fromEnvironment(
      'TRADELAB_PROFILE_CHART', defaultValue: false);
  static const sampleSize = 120;

  final List<int> _buildUs = [];
  final List<int> _rasterUs = [];
  final List<int> _totalUs = [];
  bool _attached = false;

  static int percentileUs(List<int> measurements, double percentile) {
    if (measurements.isEmpty || percentile < 0 || percentile > 1) {
      throw ArgumentError('Expected samples and percentile in [0, 1].');
    }
    final ordered = List<int>.of(measurements)..sort();
    final index = ((ordered.length - 1) * percentile).ceil();
    return ordered[index];
  }

  void attach() {
    if (!enabled || _attached) return;
    SchedulerBinding.instance.addTimingsCallback(_collect);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _attached = false;
  }

  void _collect(List<FrameTiming> timings) {
    for (final frame in timings) {
      _buildUs.add(frame.buildDuration.inMicroseconds);
      _rasterUs.add(frame.rasterDuration.inMicroseconds);
      _totalUs.add(frame.totalSpan.inMicroseconds);
      if (_totalUs.length >= sampleSize) {
        final metrics = {
          'source': 'android-flutter-frame-timing',
          'count': _totalUs.length,
          'buildP50Us': percentileUs(_buildUs, .50),
          'buildP95Us': percentileUs(_buildUs, .95),
          'rasterP95Us': percentileUs(_rasterUs, .95),
          'frameP95Us': percentileUs(_totalUs, .95),
          'frameP99Us': percentileUs(_totalUs, .99),
          'framesOver16ms': _totalUs.where((value) => value > 16667).length,
          'framesOver8ms': _totalUs.where((value) => value > 8333).length,
        };
        // No token/account/price history leaves the device.
        debugPrint('TRADELAB_CHART_FRAME_METRICS ${jsonEncode(metrics)}');
        _buildUs.clear();
        _rasterUs.clear();
        _totalUs.clear();
      }
    }
  }
}
