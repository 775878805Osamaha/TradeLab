import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Pure, testable frame sampler. It only accepts engine frame durations and
/// aggregate workload dimensions, never broker identifiers, prices, account
/// details, timestamps or market-history contents.
enum ChartFrameInteraction {
  pan,
  pinch,
  priceAxis,
  timeAxis,
  drawing,
  replaySelection,
}

class ChartInteractionFrameSampler {
  ChartInteractionFrameSampler({
    this.batchSize = 120,
    this.minimumReportSamples = 4,
  }) {
    if (batchSize < 1 || minimumReportSamples < 1 ||
        minimumReportSamples > batchSize) {
      throw ArgumentError('Invalid frame profiling sample limits');
    }
  }

  final int batchSize;
  final int minimumReportSamples;

  final List<int> _buildUs = <int>[];
  final List<int> _rasterUs = <int>[];
  final List<int> _totalUs = <int>[];

  ChartFrameInteraction? _interaction;
  String _chartMode = '';
  bool _replay = false;
  int _displayedCandles = 0;
  int _rangeBidTicks = 0;

  bool get active => _interaction != null;
  int get pendingSamples => _totalUs.length;

  /// Changing between a one-finger pan and pinch starts a clean cohort.
  /// Returns statistics from the preceding interaction only if the cohort
  /// contained enough actual engine frames to be meaningful.
  Map<String, Object>? start({
    required ChartFrameInteraction interaction,
    required String chartMode,
    required bool replay,
    required int displayedCandles,
    required int rangeBidTicks,
  }) {
    if (displayedCandles < 0 || rangeBidTicks < 0 ||
        !const <String>['candles', 'range', 'heikinAshi'].contains(chartMode)) {
      throw ArgumentError('Invalid chart workload descriptor');
    }
    if (_interaction == interaction && _chartMode == chartMode &&
        _replay == replay) {
      return null;
    }
    final previous = _summary();
    _clear();
    _interaction = interaction;
    _chartMode = chartMode;
    _replay = replay;
    // Snapshot the workload once. Changing chart data mid-gesture must not
    // silently relabel already collected frame durations.
    _displayedCandles = displayedCandles;
    _rangeBidTicks = rangeBidTicks;
    return previous;
  }

  Map<String, Object>? record({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
  }) {
    if (_interaction == null) return null;
    if (buildUs < 0 || rasterUs < 0 || totalUs < 0) {
      throw ArgumentError('Engine frame durations must not be negative');
    }
    _buildUs.add(buildUs);
    _rasterUs.add(rasterUs);
    _totalUs.add(totalUs);
    if (_totalUs.length < batchSize) return null;
    final report = _summary();
    _clear();
    return report;
  }

  /// End at release, so off-gesture menu/toolbar frames never contaminate
  /// the p95 of user drag or pinch interactions.
  Map<String, Object>? end() {
    final report = _summary();
    _clear();
    _interaction = null;
    _chartMode = '';
    _replay = false;
    _displayedCandles = 0;
    _rangeBidTicks = 0;
    return report;
  }

  Map<String, Object>? _summary() {
    if (_interaction == null ||
        _totalUs.length < minimumReportSamples) return null;
    return <String, Object>{
      'source': 'flutter-engine-frame-timing',
      'interaction': _interaction!.name,
      'mode': _chartMode,
      'replay': _replay,
      'displayedCandles': _displayedCandles,
      'rangeBidTicks': _rangeBidTicks,
      'count': _totalUs.length,
      'buildP50Us': ChartFrameProfiler.percentileUs(_buildUs, .50),
      'buildP95Us': ChartFrameProfiler.percentileUs(_buildUs, .95),
      'rasterP95Us': ChartFrameProfiler.percentileUs(_rasterUs, .95),
      'frameP95Us': ChartFrameProfiler.percentileUs(_totalUs, .95),
      'frameP99Us': ChartFrameProfiler.percentileUs(_totalUs, .99),
      'framesOver16ms': _totalUs.where((value) => value > 16667).length,
      'framesOver8ms': _totalUs.where((value) => value > 8333).length,
    };
  }

  void _clear() {
    _buildUs.clear();
    _rasterUs.clear();
    _totalUs.clear();
  }
}

/// Opt-in REAL engine frame timing, scoped to gestures. Previously this
/// profiler aggregated every frame while ChartScreen was mounted, including
/// menus and idle app activity, making pan/pinch p95 uninterpretable.
///
/// Enable on an actual Android device only for a controlled measurement:
/// flutter run --profile --dart-define=TRADELAB_PROFILE_CHART=true
/// This code does not run profiling or claim Android FPS by itself.
class ChartFrameProfiler {
  static const enabled = bool.fromEnvironment(
      'TRADELAB_PROFILE_CHART', defaultValue: false);
  static const sampleSize = 120;

  final ChartInteractionFrameSampler _sampler =
      ChartInteractionFrameSampler(batchSize: sampleSize);
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

  void beginInteraction({
    required ChartFrameInteraction interaction,
    required String chartMode,
    required bool replay,
    required int displayedCandles,
    required int rangeBidTicks,
  }) {
    if (!enabled || !_attached) return;
    _emit(_sampler.start(
      interaction: interaction,
      chartMode: chartMode,
      replay: replay,
      displayedCandles: displayedCandles,
      rangeBidTicks: rangeBidTicks,
    ));
  }

  void endInteraction() {
    if (!enabled || !_attached) return;
    _emit(_sampler.end());
  }

  void detach() {
    if (!_attached) return;
    _emit(_sampler.end());
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _attached = false;
  }

  void _collect(List<FrameTiming> timings) {
    if (!_sampler.active) return;
    for (final frame in timings) {
      _emit(_sampler.record(
        buildUs: frame.buildDuration.inMicroseconds,
        rasterUs: frame.rasterDuration.inMicroseconds,
        totalUs: frame.totalSpan.inMicroseconds,
      ));
    }
  }

  static void _emit(Map<String, Object>? metrics) {
    if (metrics == null) return;
    // No account IDs, broker symbols, trade details or market prices are
    // ever included. In normal builds profiling is disabled entirely.
    debugPrint('TRADELAB_CHART_FRAME_METRICS ${jsonEncode(metrics)}');
  }
}
