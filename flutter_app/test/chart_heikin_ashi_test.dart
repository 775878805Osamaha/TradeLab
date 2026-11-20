import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_heikin_ashi.dart';
import 'package:tradelab_flutter/chart/candle_prefix.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

void main() {
  const sample = <TradeCandle>[
    TradeCandle(10, 15, 9, 14),
    TradeCandle(14, 17, 11, 12),
    TradeCandle(12, 19, 10, 16),
    TradeCandle(16, 18, 14, 17),
  ];

  List<TradeCandle> legacy(List<TradeCandle> raw) {
    if (raw.isEmpty) return const <TradeCandle>[];
    final result = <TradeCandle>[];
    var previousOpen = (raw.first.open + raw.first.close) / 2;
    var previousClose =
        (raw.first.open + raw.first.high + raw.first.low + raw.first.close) / 4;
    for (final current in raw) {
      final close =
          (current.open + current.high + current.low + current.close) / 4;
      final open =
          result.isEmpty ? previousOpen : (previousOpen + previousClose) / 2;
      result.add(TradeCandle(
        open,
        math.max(current.high, math.max(open, close)),
        math.min(current.low, math.min(open, close)),
        close,
      ));
      previousOpen = open;
      previousClose = close;
    }
    return result;
  }

  void expectSameOhlc(TradeCandle actual, TradeCandle expected) {
    expect(actual.open, expected.open);
    expect(actual.high, expected.high);
    expect(actual.low, expected.low);
    expect(actual.close, expected.close);
  }

  test('matches the exact pre-existing causal HA algorithm', () {
    final output = ChartHeikinAshi.build(sample);
    final baseline = legacy(sample);
    expect(output, hasLength(sample.length));
    for (var i = 0; i < output.length; i++) {
      expectSameOhlc(output[i], baseline[i]);
    }
    expect(sample.first.open, 10);
    expect(sample.last.close, 17);
  });

  test('Heikin-Ashi future bars are still hidden by Replay prefix', () {
    final generated = ChartHeikinAshi.build(sample);
    final prefix = CandlePrefix(generated, 2);
    expect(prefix, hasLength(2));
    expectSameOhlc(prefix[0], generated[0]);
    expectSameOhlc(prefix[1], generated[1]);
    expect(() => prefix[2], throwsRangeError);
    expect(sample.last.close, 17);
  });

  test('small histories return immediately with source identity caching', () {
    final cache = ChartHeikinAshiCache();
    var ready = 0;
    final first = cache.resolve(sample, onReady: () => ready++);
    final second = cache.resolve(sample, onReady: () => ready++);
    expect(identical(first, second), isTrue);
    expect(ready, 0);
    expect(cache.isPendingFor(sample), isFalse);
    cache.dispose();
    expect(cache.resolve(sample, onReady: () => ready++), isNull);
  });

  test('offload threshold prevents large transformations on touch isolate', () {
    expect(ChartHeikinAshi.minOffloadCandles, 5000);
    expect(ChartHeikinAshi.shouldOffload(4999), isFalse);
    expect(ChartHeikinAshi.shouldOffload(5000), !kIsWeb);
    expect(ChartHeikinAshi.shouldOffload(100000), !kIsWeb);
  });

  test('100k real-price candles are transformed by worker without altering source',
      () async {
    final raw = List<TradeCandle>.generate(100001, (i) {
      final open = 3980.0 + i * .001;
      final close = open + (i.isEven ? .12 : -.09);
      return TradeCandle(
        open,
        math.max(open, close) + .18,
        math.min(open, close) - .11,
        close,
      );
    }, growable: false);
    final actual = await ChartHeikinAshi.buildAsync(raw);
    final baseline = legacy(raw);
    expect(actual, hasLength(100001));
    for (final i in [0, 1, 2, 999, 4999, 5000, 50001, 99999, 100000]) {
      expectSameOhlc(actual[i], baseline[i]);
      expect(raw[i].open, 3980.0 + i * .001);
    }
    final prefix = CandlePrefix(actual, 600);
    expect(prefix, hasLength(600));
    expect(() => prefix[600], throwsRangeError);
  });

  test('new market source wins when an older worker completes late', () async {
    if (kIsWeb) return;
    const candleA = TradeCandle(10, 12, 9, 11);
    const candleB = TradeCandle(20, 23, 18, 22);
    final sourceA = List<TradeCandle>.filled(5000, candleA);
    final sourceB = List<TradeCandle>.filled(5000, candleB);
    final deferredA = Completer<List<TradeCandle>>();
    final deferredB = Completer<List<TradeCandle>>();
    var requestedA = 0;
    var requestedB = 0;
    final cache = ChartHeikinAshiCache(buildLarge: (source) {
      if (identical(source, sourceA)) {
        requestedA++;
        return deferredA.future;
      }
      if (identical(source, sourceB)) {
        requestedB++;
        return deferredB.future;
      }
      throw StateError('Unexpected data source');
    });
    final notifications = <String>[];
    expect(cache.resolve(sourceA,
        onReady: () => notifications.add('old')), isNull);
    expect(cache.resolve(sourceA,
        onReady: () => notifications.add('duplicate')), isNull);
    expect(requestedA, 1);
    expect(cache.isPendingFor(sourceA), isTrue);
    expect(cache.resolve(sourceB,
        onReady: () => notifications.add('new')), isNull);
    expect(requestedB, 1);
    deferredA.complete([candleA]);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, isEmpty);
    expect(cache.resolve(sourceB,
        onReady: () => notifications.add('extra')), isNull);
    expect(requestedB, 1);
    deferredB.complete([candleB]);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, ['new']);
    expect(cache.isPendingFor(sourceB), isFalse);
    expect(cache.resolve(sourceB, onReady: () {} )!.single.close, 22);
    cache.dispose();
  });

  test('failed preparation does not loop and can recover with new source',
      () async {
    if (kIsWeb) return;
    const candle = TradeCandle(10, 12, 9, 11);
    final sourceA = List<TradeCandle>.filled(5000, candle);
    final sourceB = List<TradeCandle>.filled(5000, candle);
    var requested = 0;
    var errors = 0;
    var ready = 0;
    final cache = ChartHeikinAshiCache(buildLarge: (source) {
      requested++;
      if (identical(source, sourceA)) {
        return Future<List<TradeCandle>>.error(StateError('worker'));
      }
      return Future<List<TradeCandle>>.value([candle]);
    });
    expect(cache.resolve(sourceA, onReady: () => ready++,
        onError: () => errors++), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(errors, 1);
    expect(cache.resolve(sourceA, onReady: () => ready++,
        onError: () => errors++), isNull);
    expect(requested, 1);
    expect(cache.resolve(sourceB, onReady: () => ready++,
        onError: () => errors++), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(ready, 1);
    expect(cache.resolve(sourceB, onReady: () => ready++)!.single.close, 11);
    cache.dispose();
  });

  test('disposal suppresses late worker redraw', () async {
    if (kIsWeb) return;
    const candle = TradeCandle(10, 12, 9, 11);
    final source = List<TradeCandle>.filled(5000, candle);
    final deferred = Completer<List<TradeCandle>>();
    var notified = false;
    final cache = ChartHeikinAshiCache(buildLarge: (_) => deferred.future);
    expect(cache.resolve(source, onReady: () => notified = true), isNull);
    cache.dispose();
    deferred.complete([candle]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, isFalse);
    expect(cache.resolve(source, onReady: () => notified = true), isNull);
  });

  test('incremental HA append matches a full rebuild without touching past bars',
      () {
    const added = <TradeCandle>[
      TradeCandle(17, 20, 15, 19),
      TradeCandle(19, 20, 14, 15),
      TradeCandle(15, 17, 12, 16),
    ];
    final oldHA = ChartHeikinAshi.build(sample);
    final oldOpens = oldHA.map((c) => c.open).toList(growable: false);
    final newHA = ChartHeikinAshi.extendVerified(oldHA, added);
    final full = ChartHeikinAshi.build(<TradeCandle>[...sample, ...added]);
    expect(newHA, hasLength(3));
    for (var i = 0; i < added.length; i++) {
      expectSameOhlc(newHA[i], full[sample.length + i]);
    }
    expect(oldHA.map((c) => c.open), oldOpens);
    expect(sample, hasLength(4));
    expect(added, hasLength(3));
  });

  test('a cache adopts only a verified append from its exact source identity',
      () {
    final cache = ChartHeikinAshiCache();
    final sourceA = List<TradeCandle>.of(sample);
    final previous = cache.resolve(sourceA, onReady: () {})!;
    final sourceB = <TradeCandle>[
      ...sourceA,
      const TradeCandle(17, 20, 16, 19),
      const TradeCandle(19, 21, 15, 18),
    ];
    expect(cache.adoptVerifiedAppend(
      previousSource: sourceA, nextSource: sourceB, appended: 2),
      isTrue);
    final updated = cache.resolve(sourceB, onReady: () {})!;
    expect(updated, hasLength(6));
    expect(identical(updated, previous), isFalse,
        reason: 'Do not mutate an existing Replay/painter snapshot');
    final baseline = ChartHeikinAshi.build(sourceB);
    for (var i = 0; i < updated.length; i++) {
      expectSameOhlc(updated[i], baseline[i]);
    }
    expect(previous, hasLength(4));
    expect(cache.isPendingFor(sourceB), isFalse);
    cache.dispose();
  });

  test('historical prepend and different account cannot reuse HA source',
      () {
    final cache = ChartHeikinAshiCache();
    final sourceA = List<TradeCandle>.of(sample);
    cache.resolve(sourceA, onReady: () {});
    final differentSource = List<TradeCandle>.of(sample);
    final sourceB = <TradeCandle>[
      const TradeCandle(17, 20, 16, 19),
      ...sourceA,
    ];
    expect(cache.adoptVerifiedAppend(
      previousSource: differentSource, nextSource: sourceB, appended: 1),
      isFalse);
    expect(cache.adoptVerifiedAppend(
      previousSource: sourceA, nextSource: sourceB, appended: 2),
      isFalse);
    expect(cache.resolve(sourceA, onReady: () {}), hasLength(4));
    cache.dispose();
  });

  test('Replay prefix remains fixed when a verified source close is appended',
      () {
    final cache = ChartHeikinAshiCache();
    final sourceA = List<TradeCandle>.of(sample);
    final oldHA = cache.resolve(sourceA, onReady: () {})!;
    final oldReplay = CandlePrefix(oldHA, 2);
    final sourceB = <TradeCandle>[
      ...sourceA,
      const TradeCandle(17, 19, 14, 16),
    ];
    expect(cache.adoptVerifiedAppend(
      previousSource: sourceA, nextSource: sourceB, appended: 1),
      isTrue);
    final newHA = cache.resolve(sourceB, onReady: () {})!;
    final replay = CandlePrefix(newHA, 2);
    expect(replay, hasLength(2));
    expect(oldReplay, hasLength(2));
    expect(() => replay[2], throwsRangeError);
    expectSameOhlc(replay.last, oldReplay.last);
    expect(newHA.last.close, isNot(sourceB.last.close),
        reason: 'HA display is derived; source broker OHLC remains unchanged');
    cache.dispose();
  });
}
