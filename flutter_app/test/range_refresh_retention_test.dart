import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_bar_timeline.dart';
import 'package:tradelab_flutter/data/range_refresh_retention.dart';

void main() {
  const verifiedTicks = <MarketTick>[
    MarketTick(1000, 100),
    MarketTick(1001, 100.5),
    MarketTick(1002, 100.1),
  ];
  final original = RangeBarTimeline.build(verifiedTicks, .25);

  bool mayKeep({
    String? account = 'account-A',
    String? archivedAccount = 'account-A',
    String symbol = 'XAUUSD',
    String? archivedSymbol = 'XAUUSD',
    int points = 25,
    double? pointSize = .01,
    bool authorized = true,
    bool replay = false,
    List<MarketTick>? source,
    RangeBarTimeline? timeline,
  }) => RangeRefreshRetention.canKeep(
    connectedAccount: account,
    snapshotAccount: archivedAccount,
    connectedSymbol: symbol,
    snapshotSymbol: archivedSymbol,
    rangePoints: points,
    pointSize: pointSize,
    verifiedTicks: source ?? verifiedTicks,
    timeline: timeline ?? original,
    sourceReady: authorized,
    replayActive: replay,
  );

  test('same authorized BID account/symbol/point retains immutable range', () {
    expect(mayKeep(), isTrue);
    expect(original.priceDistance, .25);
    expect(original.bars, isNotEmpty);
    expect(original.endTickIndices.last, verifiedTicks.length - 1);
    expect(original.endTimestamps.last, verifiedTicks.last.timestamp);
  });

  test('account changes, signed-out source or symbol changes clear immediately', () {
    expect(mayKeep(account: 'account-B'), isFalse);
    expect(mayKeep(account: null), isFalse);
    expect(mayKeep(archivedAccount: null), isFalse);
    expect(mayKeep(symbol: 'EURUSD'), isFalse);
    expect(mayKeep(archivedSymbol: 'BTCUSDT'), isFalse);
    expect(mayKeep(authorized: false), isFalse);
  });

  test('new size/precision cannot display previous Range distance', () {
    expect(mayKeep(points: 1000), isFalse);
    expect(mayKeep(points: 10), isFalse);
    expect(mayKeep(pointSize: .001), isFalse);
    expect(mayKeep(pointSize: null), isFalse);
    expect(mayKeep(pointSize: double.nan), isFalse);
    expect(mayKeep(pointSize: 0), isFalse);
  });

  test('Replay cutoffs and corrupted source cannot be reused for live refresh', () {
    expect(mayKeep(replay: true), isFalse);
    expect(mayKeep(source: const <MarketTick>[]), isFalse);
    expect(mayKeep(source: const <MarketTick>[
      MarketTick(1000, 100), MarketTick(1001, 100.5),
      MarketTick(1002, 9999),
    ]), isFalse);
    expect(mayKeep(source: const <MarketTick>[
      MarketTick(1000, 100), MarketTick(1001, 100.5),
    ]), isFalse);
    expect(mayKeep(timeline: RangeBarTimeline.build(
        verifiedTicks, .50)), isFalse);
    expect(verifiedTicks.map((t) => t.bid), [100, 100.5, 100.1],
      reason: 'A failed refresh cannot mutate original authenticated BID');
  });
}
