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
    expect(rewound['realizedPricePnl'], 0);
    // Saving one session's empty rewind must not delete another archived
    // training session even when both were saved in the same millisecond.
    final completed = history.firstWhere(
        (entry) => entry['sessionId'] == endedSessionId);
    expect(completed['tradeCount'], 1);
  });
}
