import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_bid_page_verifier.dart';
import 'package:tradelab_flutter/data/range_older_page.dart';

void main() {
  const start = 1700000000000;
  const span = Duration(hours: 12);
  final olderBounds = RangeOlderPage.bounds(start + span.inMilliseconds);

  test('small original BID page preserves same-ms provider events', () async {
    final input = <MarketTick>[
      const MarketTick(start, 3900),
      const MarketTick(start, 3900.01),
      const MarketTick(start + 1, 3900.02),
    ];
    await RangeBidPageVerifier.verifyAsync(
      page: input, fromMs: start, toMs: start + 1,
      errorMessage: 'invalid BID event',
    );
    expect(input, hasLength(3));
    expect(input[0].timestamp, input[1].timestamp);
    expect(input[1].bid, 3900.01);
  });

  test('large 120k BID page is validated without copying results back',
      () async {
    final input = List<MarketTick>.generate(120000, (i) =>
        MarketTick(
          olderBounds.fromMs + i ~/ 2,
          3900.0 + i * .0001,
        ), growable: false);
    expect(RangeBidPageVerifier.minOffloadTicks, 5000);
    expect(RangeBidPageVerifier.shouldOffload(4999), isFalse);
    expect(RangeBidPageVerifier.shouldOffload(5000), !kIsWeb);
    final verified = await RangeOlderPage.verifyAsync(
      page: input,
      fromMs: olderBounds.fromMs,
      toMs: olderBounds.toMs,
      alreadyLoaded: 12345,
    );
    expect(identical(verified, input), isTrue);
    expect(verified.length, 120000);
    expect(verified[0].timestamp, verified[1].timestamp);
    expect(verified.last.timestamp, olderBounds.fromMs + 59999);
  });

  test('large invalid price at end of BID window is rejected, never clipped',
      () async {
    final input = List<MarketTick>.generate(6300, (i) =>
        MarketTick(start + i, 3980.0 + i * .0001));
    input[input.length - 1] = MarketTick(
      start + input.length - 1, double.nan);
    await expectLater(
      RangeBidPageVerifier.verifyAsync(
        page: input,
        fromMs: start,
        toMs: start + 9000,
        errorMessage: 'invalid BID event',
      ),
      throwsA(isA<MarketDataException>()),
    );
    expect(input.last.bid.isNaN, isTrue);
  });

  test('large disorder near final tick is rejected, not silently sorted',
      () async {
    final input = List<MarketTick>.generate(6500, (i) =>
        MarketTick(start + i, 4000.0 + i * .001));
    input[6499] = MarketTick(start + 6497, 4008.0);
    await expectLater(
      RangeOlderPage.verifyAsync(
        page: input,
        fromMs: olderBounds.fromMs,
        toMs: olderBounds.toMs,
        alreadyLoaded: 150,
      ),
      throwsA(isA<MarketDataException>()),
    );
  });

  test('older history cap remains enforced before off-isolate validation',
      () async {
    final input = List<MarketTick>.generate(5100, (i) =>
        MarketTick(olderBounds.fromMs + i, 4000));
    await expectLater(
      RangeOlderPage.verifyAsync(
        page: input,
        fromMs: olderBounds.fromMs,
        toMs: olderBounds.toMs,
        alreadyLoaded: RangeOlderPage.maxLoadedTicks - 5000,
      ),
      throwsA(isA<MarketDataException>()),
    );
    await expectLater(
      RangeOlderPage.verifyAsync(
        page: input,
        fromMs: olderBounds.fromMs + 1,
        toMs: olderBounds.toMs,
        alreadyLoaded: 0,
      ),
      throwsArgumentError,
    );
  });

  test('empty authenticated interval is accepted but invalid bounds are not',
      () async {
    await RangeBidPageVerifier.verifyAsync(
      page: const <MarketTick>[],
      fromMs: start,
      toMs: start + 20,
      errorMessage: 'invalid BID event',
    );
    await expectLater(
      RangeBidPageVerifier.verifyAsync(
        page: const <MarketTick>[],
        fromMs: start + 20,
        toMs: start,
        errorMessage: 'invalid BID event',
      ),
      throwsArgumentError,
    );
  });
}
