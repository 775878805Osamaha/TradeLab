import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/range_history_fill_policy.dart';

void main() {
  test('1000-point Range requests enough genuine bars to fill Android viewport', () {
    for (final width in <double>[260, 320, 390, 600]) {
      final target = RangeHistoryFillPolicy.targetClosedBars(
          plotWidth: width, candleWidth: 12);
      expect(target, greaterThanOrEqualTo(48));
      expect(target, greaterThanOrEqualTo((width / 12).ceil()));
      expect(target, lessThanOrEqualTo(128));
    }
  });

  test('autofill skips verified empty windows rather than mistaking them for failure', () {
    for (var page = 0; page < 4; page++) {
      expect(RangeHistoryFillPolicy.shouldContinue(
        completedPages: page,
        closedBars: 12, targetBars: 60, loadedTicks: 1000,
        authenticatedSource: true, chartActive: true,
        historicalReplay: false, loading: false,
        historyExhausted: false, sourceError: false), isTrue);
    }
    expect(RangeHistoryFillPolicy.shouldContinue(
      completedPages: 24,
      closedBars: 12, targetBars: 60, loadedTicks: 1000,
      authenticatedSource: true, chartActive: true,
      historicalReplay: false, loading: false,
      historyExhausted: false, sourceError: false), isFalse);
  });

  test('never searches beyond strict memory, broker or Replay safety bounds', () {
    final cases = [
      (100, true, true, false, false, false, false),
      (1, false, true, false, false, false, false),
      (1, true, false, false, false, false, false),
      (1, true, true, true, false, false, false),
      (1, true, true, false, true, false, false),
      (1, true, true, false, false, true, false),
      (1, true, true, false, false, false, true),
    ];
    for (final testCase in cases) {
      expect(RangeHistoryFillPolicy.shouldContinue(
        completedPages: 0, closedBars: testCase.$1,
        targetBars: 48, loadedTicks: 100,
        authenticatedSource: testCase.$2,
        chartActive: testCase.$3,
        historicalReplay: testCase.$4,
        loading: testCase.$5,
        historyExhausted: testCase.$6,
        sourceError: testCase.$7), isFalse);
    }
    expect(RangeHistoryFillPolicy.shouldContinue(
      completedPages: 0, closedBars: 0, targetBars: 48,
      loadedTicks: 1000000, authenticatedSource: true,
      chartActive: true, historicalReplay: false,
      loading: false, historyExhausted: false, sourceError: false), isFalse);
  });

  test('invalid viewport metrics fail safe without faking additional candles', () {
    expect(RangeHistoryFillPolicy.targetClosedBars(
      plotWidth: double.nan, candleWidth: 0), 48);
    expect(RangeHistoryFillPolicy.targetClosedBars(
      plotWidth: 1e7, candleWidth: 1), 128);
  });
  test('manual BID history request requires verified connected Range chart', () {
    bool permitted({
      bool rangeMode = true,
      bool connected = true,
      bool hasAccount = true,
      bool hasVerifiedTicks = true,
      int loadedTicks = 1,
      bool chartActive = true,
      bool initialLoading = false,
      bool olderLoading = false,
      bool autoFilling = false,
      bool historyExhausted = false,
      bool replayActive = false,
      bool selectingReplayStart = false,
    }) => RangeHistoryFillPolicy.canRequestOlderManually(
      rangeMode: rangeMode,
      connected: connected,
      hasAccount: hasAccount,
      hasVerifiedTicks: hasVerifiedTicks,
      loadedTicks: loadedTicks,
      chartActive: chartActive,
      initialLoading: initialLoading,
      olderLoading: olderLoading,
      autoFilling: autoFilling,
      historyExhausted: historyExhausted,
      replayActive: replayActive,
      selectingReplayStart: selectingReplayStart,
    );
    expect(permitted(), isTrue);
    expect(permitted(rangeMode: false), isFalse);
    expect(permitted(connected: false), isFalse);
    expect(permitted(hasAccount: false), isFalse);
    expect(permitted(hasVerifiedTicks: false), isFalse,
        reason: 'No fake broker history paging from an empty chart');
    expect(permitted(loadedTicks: 0), isFalse);
    expect(permitted(loadedTicks: 999999), isTrue);
    expect(permitted(loadedTicks: 1000000), isFalse,
        reason: 'The local memory ceiling is not broker history exhaustion');
    expect(permitted(loadedTicks: 1000001), isFalse);
    expect(permitted(chartActive: false), isFalse);
    expect(permitted(initialLoading: true), isFalse);
    expect(permitted(olderLoading: true), isFalse);
    expect(permitted(autoFilling: true), isFalse);
    expect(permitted(historyExhausted: true), isFalse);
    expect(permitted(replayActive: true), isFalse);
    expect(permitted(selectingReplayStart: true), isFalse);
  });

  test('stale broker response cannot block newly chosen Range symbol', () {
    final gate = RangeAutoFillRevisionGate();
    expect(gate.start(7), isTrue);
    expect(gate.start(7), isFalse,
        reason: 'Duplicate backfills for one symbol must never overlap');
    expect(gate.isActiveFor(7), isTrue);
    // User selected another cTrader symbol while revision 7 still awaits
    // network ticks. Revision 8 is now allowed to start immediately.
    expect(gate.start(8), isTrue);
    expect(gate.isActiveFor(7), isFalse);
    expect(gate.isActiveFor(8), isTrue);
    gate.finish(7);
    expect(gate.isActiveFor(8), isTrue,
        reason: 'Old network completion must not clear new download state');
    expect(gate.start(8), isFalse);
    gate.finish(8);
    expect(gate.isActiveFor(8), isFalse);
    expect(gate.start(9), isTrue);
  });

  test('unknown revisions never steal live Range load', () {
    final gate = RangeAutoFillRevisionGate();
    expect(gate.start(-1), isFalse);
    expect(gate.start(12), isTrue);
    gate.finish(13);
    expect(gate.isActiveFor(12), isTrue);
    gate.finish(12);
    expect(gate.isActiveFor(12), isFalse);
  });

}
