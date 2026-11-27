import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/range_older_page.dart';

void main() {
  final earliest = DateTime.utc(2026, 11, 12, 16).millisecondsSinceEpoch;

  test('older page uses only the exact twelve hours before displayed ticks', () {
    final end = earliest - 1; // Strictly before the first displayed event.
    final page = RangeOlderPage.bounds(end);
    expect(page.toMs, earliest - 1);
    expect(page.fromMs, end - const Duration(hours: 12).inMilliseconds);
    expect(page.toMs - page.fromMs,
        const Duration(hours: 12).inMilliseconds);
  });

  test('valid BID page preserves broker order and same-ms multiplicity', () {
    final end = earliest - 1;
    final page = RangeOlderPage.bounds(end);
    final input = <MarketTick>[
      MarketTick(page.fromMs, 3900),
      MarketTick(page.fromMs, 3900.10),
      MarketTick(page.toMs, 3901),
      MarketTick(page.toMs, 3901.30),
    ];
    final verified = RangeOlderPage.verify(
        page: input, fromMs: page.fromMs, toMs: page.toMs,
        alreadyLoaded: 8000);
    expect(identical(verified, input), isTrue);
    expect(verified.map((t) => t.timestamp), [
      page.fromMs, page.fromMs, end, end,
    ]);
    expect(verified.map((t) => t.bid), [3900, 3900.10, 3901, 3901.30]);
  });

  test('reject future, prior and unordered ticks instead of clipping', () {
    final page = RangeOlderPage.bounds(earliest - 1);
    for (final incoming in <List<MarketTick>>[
      [MarketTick(page.fromMs - 1, 3900)],
      [MarketTick(page.toMs + 1, 3900)],
      [MarketTick(page.toMs, 3900),
       MarketTick(page.fromMs, 3901)],
      [MarketTick(page.fromMs, double.nan)],
      [MarketTick(page.fromMs, 0)],
    ]) {
      expect(() => RangeOlderPage.verify(
        page: incoming, fromMs: page.fromMs, toMs: page.toMs,
        alreadyLoaded: 50),
        throwsA(isA<MarketDataException>()));
    }
  });

  test('reject incorrect page bounds and oversized tick history', () {
    expect(() => RangeOlderPage.bounds(123), throwsRangeError);
    final page = RangeOlderPage.bounds(earliest - 1);
    expect(() => RangeOlderPage.verify(
        page: const [], fromMs: page.fromMs + 1, toMs: page.toMs,
        alreadyLoaded: 0), throwsArgumentError);
    expect(() => RangeOlderPage.verify(
        page: [MarketTick(page.toMs, 3900)], fromMs: page.fromMs,
        toMs: page.toMs, alreadyLoaded: RangeOlderPage.maxLoadedTicks),
        throwsA(isA<MarketDataException>()));
  });

  test('an empty verified broker interval can be paged through safely', () {
    final bounds = RangeOlderPage.bounds(earliest - 1);
    final verified = RangeOlderPage.verify(
        page: const [], fromMs: bounds.fromMs, toMs: bounds.toMs,
        alreadyLoaded: 2500);
    expect(verified, isEmpty);
    final next = RangeOlderPage.bounds(bounds.fromMs - 1);
    expect(next.toMs, bounds.fromMs - 1);
  });

  test('120k authenticated older BID events need one boundary read, not a scan',
      () async {
    final currentFirst = DateTime.utc(2026, 11, 20).millisecondsSinceEpoch;
    final bounds = RangeOlderPage.bounds(currentFirst - 1);
    final source = List<MarketTick>.generate(120000,
        (index) => MarketTick(bounds.fromMs + index ~/ 2, 3900.0 + index * .001),
        growable: false);
    // Establish the scanner's source-ordering precondition using the actual
    // async worker verifier, not an invented trusted/sorted fixture label.
    final verified = await RangeOlderPage.verifyAsync(
      page: source, fromMs: bounds.fromMs, toMs: bounds.toMs,
      alreadyLoaded: 32000);
    expect(identical(verified, source), isTrue);
    final measured = _ReadCountTicks(source);
    expect(RangeOlderPage.overlapsLoadedHistory(
      sortedVerifiedOlder: measured, earliestLoadedMs: currentFirst,
    ), isFalse);
    expect(measured.reads, 1,
        reason: 'After worker verification no 120k-tick second UI scan');

    measured.reads = 0;
    expect(RangeOlderPage.overlapsLoadedHistory(
      sortedVerifiedOlder: measured, earliestLoadedMs: source.last.timestamp,
    ), isTrue,
        reason: 'BID events sharing one millisecond must never be merged');
    expect(measured.reads, 1);
  });

  test('exact older-page overlaps reject same-ms boundary and later prices',
      () {
    const firstCurrent = 1000;
    expect(RangeOlderPage.overlapsLoadedHistory(
      sortedVerifiedOlder: const [], earliestLoadedMs: firstCurrent,
    ), isFalse);
    expect(RangeOlderPage.overlapsLoadedHistory(
      sortedVerifiedOlder: [MarketTick(998, 3999), MarketTick(999, 4000)],
      earliestLoadedMs: firstCurrent,
    ), isFalse);
    expect(RangeOlderPage.overlapsLoadedHistory(
      sortedVerifiedOlder: [MarketTick(998, 3999), MarketTick(1000, 4000)],
      earliestLoadedMs: firstCurrent,
    ), isTrue);
    expect(RangeOlderPage.overlapsLoadedHistory(
      sortedVerifiedOlder: [MarketTick(998, 3999), MarketTick(1001, 4000)],
      earliestLoadedMs: firstCurrent,
    ), isTrue);
  });
}

/// Counts only the indexed BID reads performed after worker page validation.
class _ReadCountTicks extends ListBase<MarketTick> {
  _ReadCountTicks(this.source);
  final List<MarketTick> source;
  int reads = 0;

  @override
  int get length => source.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Verified source tick archive is read-only');

  @override
  MarketTick operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, MarketTick value) =>
      throw UnsupportedError('Verified source tick archive is read-only');
}
