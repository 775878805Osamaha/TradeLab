import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_load_profiler.dart';

void main() {
  test('profiling is disabled unless explicitly enabled for Android Profile',
      () {
    expect(ChartLoadProfiler.enabled, isFalse);
    expect(const ChartLoadProfiler().start(), isNull);
  });

  test('load phases produce separate, deterministic p50/p95/p99', () {
    final stats = ChartLoadStatsCollector(reportEvery: 4);
    Map<String, Object>? report;
    for (final us in [1000, 2000, 4000, 8000]) {
      report = stats.record(
        phase: ChartLoadPhase.initialCacheRead,
        durationUs: us, mode: 'candles',
        displayedBars: 4000, bidTicks: 0);
    }
    expect(report, isNotNull);
    expect(report!['phase'], 'initialCacheRead');
    expect(report['samples'], 4);
    expect(report['p50Us'], 4000);
    expect(report['p95Us'], 8000);
    expect(report['p99Us'], 8000);
    expect(report['displayedBars'], 4000);
    expect(report.containsKey('accountId'), isFalse);
    expect(report.containsKey('symbol'), isFalse);
    expect(report.containsKey('price'), isFalse);
    expect(stats.sampleCount(ChartLoadPhase.olderBrokerFetch), 0);
    expect(stats.record(
      phase: ChartLoadPhase.olderBrokerFetch,
      durationUs: 990000, mode: 'candles',
      displayedBars: 4000, bidTicks: 0), isNull,
      reason: 'Broker latency must not contaminate SQLite p95');
  });

  test('candle and Range latency percentiles never mix across modes', () {
    final stats = ChartLoadStatsCollector(reportEvery: 2);
    expect(stats.record(
      phase: ChartLoadPhase.initialCacheRead,
      durationUs: 1000, mode: 'candles',
      displayedBars: 4000, bidTicks: 0), isNull);
    expect(stats.record(
      phase: ChartLoadPhase.initialCacheRead,
      durationUs: 900000, mode: 'range',
      displayedBars: 250000, bidTicks: 300000), isNull);
    final candle = stats.record(
      phase: ChartLoadPhase.initialCacheRead,
      durationUs: 2000, mode: 'candles',
      displayedBars: 4000, bidTicks: 0)!;
    expect(candle['chartMode'], 'candles');
    expect(candle['p95Us'], 2000);
    expect(stats.sampleCount(ChartLoadPhase.initialCacheRead,
      mode: 'candles'), 2);
    expect(stats.sampleCount(ChartLoadPhase.initialCacheRead,
      mode: 'range'), 1);
    final range = stats.record(
      phase: ChartLoadPhase.initialCacheRead,
      durationUs: 950000, mode: 'range',
      displayedBars: 250000, bidTicks: 300000)!;
    expect(range['chartMode'], 'range');
    expect(range['p95Us'], 950000);
  });

  test('fixed capacity rolling window evicts old outlier load samples', () {
    final stats = ChartLoadStatsCollector(
        reportEvery: 2, maxSamples: 4);
    stats.record(phase: ChartLoadPhase.olderRangeRebuild,
        durationUs: 999999, mode: 'range',
        displayedBars: 250000, bidTicks: 1000000);
    for (final t in [100, 200, 300, 400]) {
      stats.record(phase: ChartLoadPhase.olderRangeRebuild,
          durationUs: t, mode: 'range',
          displayedBars: 100, bidTicks: 500);
    }
    expect(stats.sampleCount(ChartLoadPhase.olderRangeRebuild), 4);
    final report = stats.record(
      phase: ChartLoadPhase.olderRangeRebuild,
      durationUs: 500, mode: 'range',
      displayedBars: 120, bidTicks: 800)!;
    expect(report['completedOperations'], 6);
    expect(report['samples'], 4);
    expect(report['p50Us'], 400);
    expect(report['p95Us'], 500);
    expect(report['p99Us'], 500);
    expect(report['displayedBars'], 120);
    expect(report['bidTickCount'], 800);
  });

  test('invalid durations, modes, sample limits are rejected without logs',
      () {
    expect(() => ChartLoadStatsCollector(reportEvery: 0),
        throwsArgumentError);
    expect(() => ChartLoadStatsCollector(reportEvery: 6, maxSamples: 5),
        throwsArgumentError);
    final stats = ChartLoadStatsCollector();
    expect(() => stats.record(
        phase: ChartLoadPhase.initialBrokerFetch,
        durationUs: -1, mode: 'candles',
        displayedBars: 5, bidTicks: 0), throwsArgumentError);
    expect(() => stats.record(
        phase: ChartLoadPhase.initialBrokerFetch,
        durationUs: 100, mode: 'XAUUSD',
        displayedBars: 5, bidTicks: 0), throwsArgumentError);
    expect(() => stats.record(
        phase: ChartLoadPhase.initialBrokerFetch,
        durationUs: 100, mode: 'range',
        displayedBars: -1, bidTicks: 0), throwsArgumentError);
    expect(stats.sampleCount(ChartLoadPhase.initialBrokerFetch), 0);
    expect(() => ChartLoadStatsCollector.percentileUs([], .95),
        throwsArgumentError);
    expect(() => ChartLoadStatsCollector.percentileUs([1, 2], 1.1),
        throwsArgumentError);
  });
}
