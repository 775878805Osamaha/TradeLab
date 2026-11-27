import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_training_archive.dart';
import 'package:tradelab_flutter/replay/replay_training_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Replay records stay in separate archive and undo rewound future', () async {
    final id = 'test-${DateTime.now().microsecondsSinceEpoch}';
    const source = 'binance:public:BTCUSDT:1m:candles';
    const candles = [
      TradeCandle(99, 102, 98, 100),
      TradeCandle(100, 110, 99, 108),
    ];
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    session.enter(side: ReplaySide.buy, candles: candles,
        quantity: 1, takeProfit: 105);
    session.moveTo(candles, 2);
    await ReplayTrainingArchive.save(
      sessionId: id, sourceKey: source,
      visibleCount: session.visibleCount, trades: session.trades);
    var history = await ReplayTrainingArchive.recent();
    expect(history.first['sessionId'], id);
    expect(history.first['tradeCount'], 1);
    expect(history.first['realizedPricePnl'], 5);
    expect(history.first['openTradeCount'], 0);
    expect(history.first['closedTradeCount'], 1);
    final detail = (history.first['trades'] as List).single
        as Map<String, Object?>;
    expect(detail['side'], 'buy');
    expect(detail['entryPrice'], 100);
    expect(detail['exitPrice'], 105);
    expect(detail['quantity'], 1);
    expect(detail['isOpen'], isFalse);
    expect(detail['realizedPricePnl'], 5);
    expect(detail.containsKey('sourceKey'), isFalse,
        reason: 'Individual Results rows must not contain broker account IDs');
    expect(detail.containsKey('id'), isFalse);

    // An ended Replay session clears its in-memory model. The persisted
    // archive must remain unchanged when the screen/controller is disposed.
    final endedSessionId = 'ended-${DateTime.now().microsecondsSinceEpoch}';
    await ReplayTrainingArchive.save(
      sessionId: endedSessionId, sourceKey: source,
      visibleCount: session.visibleCount, trades: session.trades);
    session.clear();
    history = await ReplayTrainingArchive.recent();
    final ended = history.firstWhere(
        (entry) => entry['sessionId'] == endedSessionId);
    expect(ended['tradeCount'], 1);
    expect(ended['realizedPricePnl'], 5);

    // A seek to before the entry must not leave a future trade in SQLite.
    session.moveTo(candles, 2);
    session.enter(side: ReplaySide.buy, candles: candles, quantity: 1);
    session.moveTo(candles, 0);
    await ReplayTrainingArchive.save(
      sessionId: id, sourceKey: source,
      visibleCount: session.visibleCount, trades: session.trades);
    history = await ReplayTrainingArchive.recent();
    final rewound = history.firstWhere((entry) => entry['sessionId'] == id);
    expect(rewound['visibleCount'], 0);
    expect(rewound['tradeCount'], 0);
    expect(rewound['openTradeCount'], 0);
    expect(rewound['closedTradeCount'], 0);
    expect(rewound['realizedPricePnl'], 0);
    expect(rewound['trades'], isEmpty,
        reason: 'Hidden future entries cannot remain in Results');
    // Saving one session's empty rewind must not delete another archived
    // training session even when both were saved in the same millisecond.
    final completed = history.firstWhere(
        (entry) => entry['sessionId'] == endedSessionId);
    expect(completed['tradeCount'], 1);
    expect(completed['closedTradeCount'], 1);
  });
  test('Results waits for a scheduled Replay write rather than showing zero',
      () async {
    final held = Completer<void>();
    ReplayTrainingArchive.trackScheduledSave(held.future);
    var readFinished = false;
    final read = ReplayTrainingArchive.recent().then((history) {
      readFinished = true;
      return history;
    });
    await Future<void>.delayed(Duration.zero);
    expect(readFinished, isFalse,
      reason: 'An active Replay write must finish before Results queries SQLite');
    held.complete();
    await read;
    expect(readFinished, isTrue);
  });

  test('Failed save surfaces as an error, but a later safe write can recover',
      () async {
    final held = Completer<void>();
    ReplayTrainingArchive.trackScheduledSave(held.future);
    final read = ReplayTrainingArchive.recent();
    held.completeError(StateError('test-only disk failure'));
    await expectLater(read, throwsStateError,
      reason: 'Never turn a failed save into a misleading zero-trade Results');
    final subsequent = Completer<void>();
    ReplayTrainingArchive.trackScheduledSave(subsequent.future);
    final nextRead = ReplayTrainingArchive.recent();
    subsequent.complete();
    await nextRead;
  });

  test('Immediate Results read sees a just-scheduled authentic Replay trade',
      () async {
    final id = 'barrier-${DateTime.now().microsecondsSinceEpoch}';
    const candles = <TradeCandle>[
      TradeCandle(98, 102, 97, 100),
      TradeCandle(100, 111, 98, 108),
    ];
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    session.enter(side: ReplaySide.buy, candles: candles, quantity: 1,
      takeProfit: 105);
    session.moveTo(candles, 2);
    final write = ReplayTrainingArchive.save(
      sessionId: id, sourceKey: 'binance:public:BTCUSDT:1m:candles',
      visibleCount: 2, trades: session.trades);
    ReplayTrainingArchive.trackScheduledSave(write);
    // Read BEFORE awaiting write: the barrier must make the completed
    // close visible, even if SQLite opened slowly on the phone.
    final history = await ReplayTrainingArchive.recent();
    final saved = history.firstWhere((item) => item['sessionId'] == id);
    expect(saved['closedTradeCount'], 1);
    expect(saved['openTradeCount'], 0);
    expect(saved['realizedPricePnl'], 5);
    await write;
  });

  test('An open Replay SELL order is visible in Results before closing', () async {
    final id = 'open-${DateTime.now().microsecondsSinceEpoch}';
    const candles = [TradeCandle(201, 204, 198, 200)];
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    session.enter(side: ReplaySide.sell, candles: candles, quantity: 3);
    final write = ReplayTrainingArchive.save(
      sessionId: id,
      sourceKey: 'ctrader:private-account:XAUUSD:1m:candles',
      visibleCount: 1,
      trades: session.trades,
    );
    ReplayTrainingArchive.trackScheduledSave(write);
    final history = await ReplayTrainingArchive.recent();
    final saved = history.firstWhere((item) => item['sessionId'] == id);
    expect(saved['openTradeCount'], 1);
    expect(saved['closedTradeCount'], 0);
    final row = (saved['trades'] as List).single as Map<String, Object?>;
    expect(row['side'], 'sell');
    expect(row['entryPrice'], 200);
    expect(row['quantity'], 3);
    expect(row['isOpen'], isTrue);
    expect(row['exitPrice'], isNull);
    expect(row['realizedPricePnl'], 0);
    expect(row.values.join(' '), isNot(contains('private-account')));
    await write;
  });


  test('Replay archive SQL pagination returns distinct ordered sessions',
      () async {
    const candles = [TradeCandle(98, 102, 97, 100)];
    final session = ReplayTrainingSession()..moveTo(candles, 1);
    session.enter(side: ReplaySide.buy, candles: candles, quantity: 1);
    final prefix = 'page-${DateTime.now().microsecondsSinceEpoch}';
    // Persist enough distinct sessions to cross the phone's first page.
    for (var index = 0; index < 25; index++) {
      await ReplayTrainingArchive.save(
        sessionId: '$prefix-$index',
        sourceKey: 'binance:public:BTCUSDT:1m:candles',
        visibleCount: 1,
        trades: session.trades,
      );
    }
    final all = await ReplayTrainingArchive.recent(limit: 50);
    final first = await ReplayTrainingArchive.recent(limit: 20);
    final second = await ReplayTrainingArchive.recent(limit: 20, offset: 20);
    expect(first.length, 20);
    expect(second, isNotEmpty);
    final joined = [...first, ...second];
    expect(
      joined.map((row) => row['sessionId']).toList(),
      all.take(joined.length).map((row) => row['sessionId']).toList(),
      reason: 'Next page must not repeat the newest five sessions or '
          'drop saved trades when timestamps tie',
    );
    expect(
      first.every((row) => row['tradeCount'] == 1),
      isTrue,
    );
    await expectLater(
        ReplayTrainingArchive.recent(offset: -1), throwsRangeError);
  });
}
