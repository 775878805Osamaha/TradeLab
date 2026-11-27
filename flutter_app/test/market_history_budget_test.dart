import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/market_history_budget.dart';

void main() {
  test('single coherent time-history budget permits >100k without overflow', () {
    expect(MarketHistoryBudget.maxVisibleTimeCandles, 200000);
    for (final length in [0, 100001, 200000]) {
      MarketHistoryBudget.requireCapacity(length);
    }
    for (final length in [-1, 200001]) {
      expect(() => MarketHistoryBudget.requireCapacity(length),
          throwsA(isA<MarketDataException>()));
    }
  });
}
