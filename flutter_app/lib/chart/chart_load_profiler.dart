import 'dart:convert';

import 'package:flutter/foundation.dart';

/// No broker/account/symbol, prices, timestamps, session tokens or orders
/// ever enter this opt-in Android Profile logging path.
enum ChartLoadPhase {
  initialCacheRead,
  initialCacheSnapshot,
  initialBrokerFetch,
  initialBrokerMerge,
  rangeStartup,
  olderCacheRead,
  olderBrokerFetch,
  olderCandlePrepend,
  olderRangeScan,
  olderRangeRebuild,
  closedCandleFetch,
  closedCandleMerge,
}

/// Pure, deterministic rolling latency statistics suitable for unit tests.
/// A cohort contains timings for ONE operation class only; p95/p99 from cache
/// reads must not be polluted by broker waits or isolate work. The ring is
/// bounded and cannot grow with hours of open-chart activity.
class ChartLoadStatsCollector {
  ChartLoadStatsCollector({this.reportEvery = 4, this.maxSamples = 40}) {
    if (reportEvery < 1 || maxSamples < reportEvery) {
      throw ArgumentError('Invalid chart load timing sample configuration');
    }
  }

  final int reportEvery;
  final int maxSamples;
  final Map<ChartLoadPhase, List<int>> _byPhase = {};
  final Map<ChartLoadPhase, int> _totals = {};

  int sampleCount(ChartLoadPhase phase) => _byPhase[phase]?.length ?? 0;

  static int percentileUs(List<int> values, double percentile) {
    if (values.isEmpty || percentile < 0 || percentile > 1) {
      throw ArgumentError('Invalid load time percentile request');
    }
    final sorted = List<int>.of(values)..sort();
    return sorted[((sorted.length - 1) * percentile).ceil()];
  }

  Map<String, Object>? record({
    required ChartLoadPhase phase,
    required int durationUs,
    required String mode,
    required int displayedBars,
    required int bidTicks,
  }) {
    if (durationUs < 0 || displayedBars < 0 || bidTicks < 0 ||
        !const ['candles', 'heikinAshi', 'range'].contains(mode)) {
      throw ArgumentError('Invalid chart load timing and workload');
    }
    final samples = _byPhase.putIfAbsent(phase, () => <int>[]);
    samples.add(durationUs);
    if (samples.length > maxSamples) samples.removeAt(0);
    final total = (_totals[phase] ?? 0) + 1;
    _totals[phase] = total;
    if (total % reportEvery != 0) return null;
    return <String, Object>{
      'type': 'rolling-source-load-time',
      'phase': phase.name,
      'chartMode': mode,
      'samples': samples.length,
      'completedOperations': total,
      'displayedBars': displayedBars,
      'bidTickCount': bidTicks,
      'p50Us': percentileUs(samples, .50),
      'p95Us': percentileUs(samples, .95),
      'p99Us': percentileUs(samples, .99),
    };
  }
}

/// Reuses the established opt-in chart Profile switch. No work or logs are
/// generated in normal releases. These are *actual stopwatch durations* on
/// the user's device, not synthetic FPS estimates or broker connection tests.
class ChartLoadProfiler {
  const ChartLoadProfiler();
  static const enabled = bool.fromEnvironment(
    'TRADELAB_PROFILE_CHART', defaultValue: false);
  static final ChartLoadStatsCollector _stats = ChartLoadStatsCollector();

  Stopwatch? start() => enabled ? (Stopwatch()..start()) : null;

  void finish(Stopwatch? clock, {
    required ChartLoadPhase phase,
    required String mode,
    required int displayedBars,
    required int bidTicks,
  }) {
    if (!enabled || clock == null) return;
    clock.stop();
    final durationUs = clock.elapsedMicroseconds;
    // Every completed page gives a useful, sanitized diagnostic even if a
    // profile session has not yet collected four repeats for a percentile.
    debugPrint('TRADELAB_CHART_LOAD_EVENT ${jsonEncode(<String, Object>{
      'phase': phase.name,
      'mode': mode,
      'durationUs': durationUs,
      'displayedBars': displayedBars,
      'bidTickCount': bidTicks,
    })}');
    final aggregate = _stats.record(
      phase: phase,
      durationUs: durationUs,
      mode: mode,
      displayedBars: displayedBars,
      bidTicks: bidTicks,
    );
    if (aggregate != null) {
      debugPrint('TRADELAB_CHART_LOAD_METRICS ${jsonEncode(aggregate)}');
    }
  }
}
