import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/replay/replay_lab_bridge.dart';

void main() {
  test('a 100k-bar chart exposes a frozen prefix without eager copying', () {
    final source = _ReadCountingHistory();
    final prefix = FrozenMarketBarPrefix(source, 3);

    expect(prefix.length, 3);
    expect(source.readCount, 0,
      reason: 'capturing Replay must not enumerate 100k bars');
    expect(prefix[2].timestamp, 3);
    expect(source.readCount, 1);
    expect(() => prefix[3], throwsRangeError,
      reason: 'unrevealed future bars must remain inaccessible');
    expect(() => prefix[0] = const MarketBar(1,
      TradeCandle(10, 10, 10, 10)), throwsUnsupportedError);
    expect(() => prefix.length = 4, throwsUnsupportedError);
    expect(source.readCount, 1);
  });

  test('an older captured history generation stays unchanged after prepend', () {
    const candle = TradeCandle(100, 100, 100, 100);
    final oldHistory = List<MarketBar>.unmodifiable([
      const MarketBar(100, candle),
      const MarketBar(200, candle),
      const MarketBar(300, candle),
    ]);
    final snapshot = ReplayLabSnapshot(accountKey: 'ctrader:1',
      symbol: 'XAUUSD', timeframe: '1m',
      bars: FrozenMarketBarPrefix(oldHistory, 2));
    final newHistory = List<MarketBar>.unmodifiable([
      const MarketBar(50, candle),
      ...oldHistory,
    ]);

    expect(snapshot.bars.map((bar) => bar.timestamp).toList(), [100, 200]);
    expect(newHistory.map((bar) => bar.timestamp).toList(), [50, 100, 200, 300]);
    expect(() => oldHistory[0] = const MarketBar(1, candle),
      throwsUnsupportedError);
    expect(() => FrozenMarketBarPrefix(oldHistory, 4), throwsRangeError);
    expect(() => FrozenMarketBarPrefix(oldHistory, -1), throwsRangeError);
  });
}

class _ReadCountingHistory extends ListBase<MarketBar> {
  int readCount = 0;

  @override
  int get length => 100100;

  @override
  set length(int value) => throw UnsupportedError('Test history is read-only');

  @override
  MarketBar operator [](int index) {
    if (index < 0 || index >= length) throw RangeError.index(index, this);
    readCount++;
    if (index >= 3) throw StateError('Read an unrevealed future bar');
    return MarketBar(index + 1, const TradeCandle(100, 100, 100, 100));
  }

  @override
  void operator []=(int index, MarketBar value) =>
      throw UnsupportedError('Test history is read-only');
}
