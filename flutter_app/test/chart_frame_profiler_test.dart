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

  test('isolates pan frames from later pinch frames and idle updates', () {
    final sampler = ChartInteractionFrameSampler(
      batchSize: 8, minimumReportSamples: 4);
    expect(sampler.record(buildUs: 1000, rasterUs: 3000, totalUs: 5000),
        isNull, reason: 'Idle frames must not enter touch measurements');
    expect(sampler.pendingSamples, 0);
    expect(sampler.start(
      interaction: ChartFrameInteraction.pan,
      chartMode: 'range',
      replay: false,
      displayedCandles: 120000,
      rangeBidTicks: 300000,
    ), isNull);
    for (var frame = 0; frame < 5; frame++) {
      expect(sampler.record(
        buildUs: 1000 + frame * 1000,
        rasterUs: 2000 + frame * 2000,
        totalUs: 5000 + frame * 5000,
      ), isNull);
    }
    final pan = sampler.start(
      interaction: ChartFrameInteraction.pinch,
      chartMode: 'range', replay: false,
      displayedCandles: 120000, rangeBidTicks: 300000,
    )!;
    expect(pan['interaction'], 'pan');
    expect(pan['mode'], 'range');
    expect(pan['replay'], isFalse);
    expect(pan['displayedCandles'], 120000);
    expect(pan['rangeBidTicks'], 300000);
    expect(pan['count'], 5);
    expect(pan['buildP50Us'], 3000);
    expect(pan['buildP95Us'], 5000);
    expect(pan['rasterP95Us'], 10000);
    expect(pan['frameP95Us'], 25000);
    expect(pan['framesOver16ms'], 2);
    expect(pan['framesOver8ms'], 4);
    expect(pan.containsKey('price'), isFalse);
    expect(pan.containsKey('account'), isFalse);
    expect(pan.containsKey('symbol'), isFalse);
    expect(sampler.pendingSamples, 0,
        reason: 'Pinch cannot inherit pan frame timings');

    for (var i = 0; i < 4; i++) {
      expect(sampler.record(
        buildUs: 800, rasterUs: 900, totalUs: 2000,
      ), isNull);
    }
    final pinch = sampler.end()!;
    expect(pinch['interaction'], 'pinch');
    expect(pinch['count'], 4);
    expect(pinch['framesOver16ms'], 0);
    expect(sampler.record(
      buildUs: 10000, rasterUs: 10000, totalUs: 20000,
    ), isNull);
    expect(sampler.pendingSamples, 0);
    expect(sampler.end(), isNull);
  });

  test('engine timing reports complete 120-frame cohorts without mixing',
      () {
    final sampler = ChartInteractionFrameSampler();
    sampler.start(
      interaction: ChartFrameInteraction.timeAxis,
      chartMode: 'candles',
      replay: false,
      displayedCandles: 200, rangeBidTicks: 0);
    Map<String, Object>? batch;
    for (var i = 0; i < 120; i++) {
      final report = sampler.record(
        buildUs: 2000, rasterUs: 3500,
        totalUs: i.isEven ? 9000 : 17000,
      );
      if (i < 119) expect(report, isNull);
      batch = report ?? batch;
    }
    expect(batch, isNotNull);
    expect(batch!['interaction'], 'timeAxis');
    expect(batch['mode'], 'candles');
    expect(batch['count'], 120);
    expect(batch['framesOver16ms'], 60);
    expect(batch['framesOver8ms'], 120);
    expect(sampler.pendingSamples, 0,
        reason: 'Next engine frame belongs to a new capped cohort');
    expect(sampler.end(), isNull);
  });

  test('short, abandoned gestures are never reported as stable p95', () {
    final sampler = ChartInteractionFrameSampler(
      batchSize: 120, minimumReportSamples: 4);
    sampler.start(
      interaction: ChartFrameInteraction.pan,
      chartMode: 'heikinAshi', replay: true,
      displayedCandles: 42, rangeBidTicks: 0);
    for (var i = 0; i < 3; i++) {
      sampler.record(
        buildUs: 1000, rasterUs: 2000, totalUs: 3000);
    }
    expect(sampler.end(), isNull);
    expect(sampler.pendingSamples, 0);
    expect(sampler.active, isFalse);
  });

  test('same active phase does not reset accumulated pinch samples', () {
    final sampler = ChartInteractionFrameSampler(
      batchSize: 120, minimumReportSamples: 4);
    sampler.start(
      interaction: ChartFrameInteraction.pinch,
      chartMode: 'range', replay: true,
      displayedCandles: 14, rangeBidTicks: 5000);
    for (var i = 0; i < 4; i++) {
      sampler.record(
        buildUs: 1000, rasterUs: 1000, totalUs: 3000);
      expect(sampler.start(
        interaction: ChartFrameInteraction.pinch,
        chartMode: 'range', replay: true,
        displayedCandles: 15 + i, rangeBidTicks: 5200 + i,
      ), isNull);
    }
    final report = sampler.end()!;
    expect(report['count'], 4);
    expect(report['displayedCandles'], 14,
        reason: 'Never relabel old frames as new market data');
    expect(report['rangeBidTicks'], 5000);
  });

  test('invalid workload descriptors and durations are rejected', () {
    final sampler = ChartInteractionFrameSampler();
    expect(() => ChartInteractionFrameSampler(
      batchSize: 3, minimumReportSamples: 4,
    ), throwsArgumentError);
    expect(() => sampler.start(
      interaction: ChartFrameInteraction.pan,
      chartMode: 'BTCUSDT', replay: false,
      displayedCandles: 2, rangeBidTicks: 0,
    ), throwsArgumentError);
    expect(() => sampler.start(
      interaction: ChartFrameInteraction.pan,
      chartMode: 'range', replay: false,
      displayedCandles: -1, rangeBidTicks: 0,
    ), throwsArgumentError);
    sampler.start(
      interaction: ChartFrameInteraction.drawing,
      chartMode: 'candles', replay: false,
      displayedCandles: 100, rangeBidTicks: 0);
    expect(() => sampler.record(
      buildUs: -1, rasterUs: 0, totalUs: 0,
    ), throwsArgumentError);
    expect(sampler.pendingSamples, 0);
  });

  test('kinetic momentum starts a clean cohort after touch-up', () {
    final sampler = ChartInteractionFrameSampler(
      batchSize: 10, minimumReportSamples: 4);
    sampler.start(
      interaction: ChartFrameInteraction.pan,
      chartMode: 'candles', replay: false,
      displayedCandles: 2000, rangeBidTicks: 0);
    for (var i = 0; i < 4; i++) {
      sampler.record(buildUs: 4000, rasterUs: 6000, totalUs: 17000);
    }
    final panReport = sampler.end()!;
    expect(panReport['interaction'], 'pan');
    expect(panReport['count'], 4);
    sampler.start(
      interaction: ChartFrameInteraction.momentum,
      chartMode: 'candles', replay: false,
      displayedCandles: 2000, rangeBidTicks: 0);
    for (var i = 0; i < 4; i++) {
      sampler.record(buildUs: 1000, rasterUs: 2000, totalUs: 4000);
    }
    final flingReport = sampler.end()!;
    expect(flingReport['interaction'], 'momentum');
    expect(flingReport['count'], 4);
    expect(flingReport['framesOver16ms'], 0,
        reason: 'Fling duration samples must not inherit slower finger pan');
    expect(sampler.pendingSamples, 0);
  });

  test('cancelled momentum never includes subsequent unrelated UI frames',
      () {
    final sampler = ChartInteractionFrameSampler(
      batchSize: 10, minimumReportSamples: 4);
    sampler.start(
      interaction: ChartFrameInteraction.momentum,
      chartMode: 'range', replay: true,
      displayedCandles: 100000, rangeBidTicks: 500000);
    for (var i = 0; i < 6; i++) {
      sampler.record(buildUs: 2000, rasterUs: 5000, totalUs: 9000);
    }
    final finished = sampler.end()!;
    expect(finished['interaction'], 'momentum');
    expect(finished['count'], 6);
    expect(finished['rangeBidTicks'], 500000);
    for (var i = 0; i < 12; i++) {
      expect(sampler.record(
        buildUs: 30000, rasterUs: 30000, totalUs: 60000), isNull);
    }
    expect(sampler.pendingSamples, 0,
        reason: 'Opening account modal or a new screen cannot pollute fling');
    expect(sampler.end(), isNull);
  });
  test('delayed Flutter engine batch still belongs to the completed pan', () {
    final timing = ChartFrameTimingAttribution(
        batchSize: 10, minimumReportSamples: 4);
    expect(timing.startAt(
      frameTimeUs: 100,
      interaction: ChartFrameInteraction.pan, chartMode: 'range',
      replay: false, displayedCandles: 120000, rangeBidTicks: 500000,
    ), isEmpty);
    timing.endAt(400);
    expect(timing.active, isFalse);
    expect(timing.bufferedWindows, 1,
        reason: 'Touch-up must NOT discard engine timings still in flight');

    // The engine reports these frames AFTER touch-up: timings are batched
    // independently of scale gesture callbacks.
    final deliveredLate = timing.recordBatch([
      for (var start = 150; start <= 350; start += 50)
        (startUs: start, buildUs: 1100, rasterUs: 1800, totalUs: 19000),
    ]);
    expect(deliveredLate, isEmpty,
        reason: 'Wait until chronological delivery crosses the release');
    final flushed = timing.recordBatch([
      (startUs: 450, buildUs: 9000, rasterUs: 12000, totalUs: 30000),
    ]);
    expect(flushed, hasLength(1));
    expect(flushed.single['interaction'], 'pan');
    expect(flushed.single['mode'], 'range');
    expect(flushed.single['rangeBidTicks'], 500000);
    expect(flushed.single['count'], 5);
    expect(flushed.single['frameP95Us'], 19000,
        reason: 'Idle frame beyond release must not pollute pan p95');
    expect(timing.bufferedWindows, 0);
  });

  test('late interleaved pan and pinch batches keep exact time windows', () {
    final timing = ChartFrameTimingAttribution(
        batchSize: 10, minimumReportSamples: 4);
    timing.startAt(
      frameTimeUs: 100, interaction: ChartFrameInteraction.pan,
      chartMode: 'candles', replay: false,
      displayedCandles: 400, rangeBidTicks: 0);
    timing.endAt(350);
    timing.startAt(
      frameTimeUs: 400, interaction: ChartFrameInteraction.pinch,
      chartMode: 'candles', replay: true,
      displayedCandles: 200, rangeBidTicks: 0);
    timing.endAt(750);

    final first = timing.recordBatch([
      for (final start in [150, 200, 250, 300])
        (startUs: start, buildUs: 1000, rasterUs: 2000, totalUs: 18000),
      (startUs: 380, buildUs: 50000, rasterUs: 30000, totalUs: 90000),
      for (final start in [450, 500])
        (startUs: start, buildUs: 2000, rasterUs: 3000, totalUs: 6000),
    ]);
    expect(first, hasLength(1));
    expect(first.single['interaction'], 'pan');
    expect(first.single['count'], 4);
    expect(first.single['frameP95Us'], 18000);
    expect(first.single['replay'], isFalse);
    expect(timing.bufferedWindows, 1,
        reason: 'Pending pinch frames can arrive in a later batch');
    final second = timing.recordBatch([
      for (final start in [550, 600, 650, 700])
        (startUs: start, buildUs: 2000, rasterUs: 3000, totalUs: 6000),
      (startUs: 800, buildUs: 55000, rasterUs: 40000, totalUs: 110000),
    ]);
    expect(second, hasLength(1));
    expect(second.single['interaction'], 'pinch');
    expect(second.single['count'], 6);
    expect(second.single['frameP95Us'], 6000);
    expect(second.single['replay'], isTrue);
    expect(second.single['displayedCandles'], 200);
    expect(timing.bufferedWindows, 0);
    expect(timing.detach(), isEmpty);
  });

  test('late profiler cohort stays bounded without fabricating frames', () {
    final timing = ChartFrameTimingAttribution(
      batchSize: 120, minimumReportSamples: 4,
      maxBufferedWindows: 3,
    );
    for (var i = 0; i < 12; i++) {
      timing.startAt(
        frameTimeUs: i * 10,
        interaction: ChartFrameInteraction.pan,
        chartMode: 'range', replay: false,
        displayedCandles: 100, rangeBidTicks: 1000);
      timing.endAt(i * 10 + 5);
      expect(timing.bufferedWindows, lessThanOrEqualTo(3));
    }
    expect(timing.detach(), isEmpty,
        reason: 'Taps without rendered frames must not produce fake p95');
    expect(timing.bufferedWindows, 0);
    expect(() => ChartFrameTimingAttribution(maxBufferedWindows: 1),
        throwsArgumentError);
    expect(() => timing.recordBatch([
      (startUs: -1, buildUs: 1, rasterUs: 1, totalUs: 1),
    ]), throwsArgumentError);
  });

}
