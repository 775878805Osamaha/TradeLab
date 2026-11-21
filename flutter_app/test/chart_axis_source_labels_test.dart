import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_axis_source_labels.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';

class _ReadCountingBars extends ListBase<MarketBar> {
  _ReadCountingBars(this.source);

  final List<MarketBar> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Broker history is read-only');

  @override
  MarketBar operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, MarketBar value) =>
      throw UnsupportedError('Broker history is read-only');
}

void main() {
  const first = TradeCandle(99, 101, 98, 100);
  const second = TradeCandle(100, 103, 99, 102);
  const third = TradeCandle(102, 104, 101, 103);

  test('returns last actual previous UTC day close despite a market gap', () {
    final bars = <MarketBar>[
      MarketBar(DateTime.utc(2026, 11, 13, 19, 0).millisecondsSinceEpoch,
          first),
      MarketBar(DateTime.utc(2026, 11, 13, 19, 30).millisecondsSinceEpoch,
          second),
      // Weekend/market gap: no fake November 14 or 15 candles.
      MarketBar(DateTime.utc(2026, 11, 16, 3, 0).millisecondsSinceEpoch,
          third),
    ];
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 3), 102);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 2), isNull);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 1), isNull);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 0), isNull);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, -3), isNull);
  });

  test('handles year rollover and midnight boundaries in UTC', () {
    final bars = <MarketBar>[
      MarketBar(DateTime.utc(2025, 12, 31, 23, 59, 59).millisecondsSinceEpoch,
          first),
      MarketBar(DateTime.utc(2026, 1, 1).millisecondsSinceEpoch, second),
      MarketBar(DateTime.utc(2026, 1, 1, 23, 59).millisecondsSinceEpoch, third),
    ];
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 2), 100);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 3), 100);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 5), 100);
  });

  test('prefix-only replay ignores a future new UTC session', () {
    final firstDay = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    final secondDay = DateTime.utc(2026, 11, 19).millisecondsSinceEpoch;
    final thirdDay = DateTime.utc(2026, 11, 20).millisecondsSinceEpoch;
    final bars = <MarketBar>[
      MarketBar(firstDay + 3600000, first),
      MarketBar(secondDay + 3600000, second),
      MarketBar(secondDay + 7200000, third),
      MarketBar(thirdDay + 3600000, first),
    ];
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 3), 100);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 4), 103);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 1), isNull);
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 0), isNull);
  });

  test('120k historical source bars take logarithmic indexed reads', () {
    const count = 120000;
    final firstMs = DateTime.utc(2026, 11, 18).millisecondsSinceEpoch;
    // Test-generated fixtures do not enter the live chart or broker archive.
    // 120000 real-shaped 1-second timestamps span multiple UTC sessions.
    final data = List<MarketBar>.generate(count, (index) {
      final price = 3900.0 + index * .001;
      return MarketBar(firstMs + index * 1000,
          TradeCandle(price, price + 1, price - 1, price + .1));
    }, growable: false);
    final bars = _ReadCountingBars(data);
    final prev = ChartAxisSourceLabels.previousSessionClose(bars, count);
    expect(prev, data[86399].candle.close);
    expect(bars.reads, lessThanOrEqualTo(25),
      reason: '100k+ history must not scan the whole UTC session on rebuild');

    // An earlier Replay cutoff in the same session has no earlier day
    // and must never inspect the later hidden candles in the archive.
    bars.reads = 0;
    expect(ChartAxisSourceLabels.previousSessionClose(bars, 80000), isNull);
    expect(bars.reads, lessThanOrEqualTo(25));
  });

  test('visible high/low still reads only the requested visible span', () {
    const values = <TradeCandle>[
      TradeCandle(100, 101, 99, 100),
      TradeCandle(101, 108, 100, 102),
      TradeCandle(102, 109, 98, 103),
      TradeCandle(103, 105, 101, 104),
    ];
    expect(ChartAxisSourceLabels.visibleHighLow(values, 1, 3), (109.0, 98.0));
    expect(ChartAxisSourceLabels.visibleHighLow(values, 0, 0), isNull);
    expect(ChartAxisSourceLabels.visibleHighLow(values, 4, 6), isNull);
  });
}
