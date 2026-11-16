import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/data/market_api.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
import 'package:tradelab_flutter/paper/paper_journal_controller.dart';
import 'package:tradelab_flutter/paper/paper_journal_store.dart';
import 'package:tradelab_flutter/paper/paper_ledger.dart';
import 'package:tradelab_flutter/paper/paper_trade_service.dart';

class _QuoteProvider implements PaperQuoteProvider {
  _QuoteProvider(this.quote);
  MarketQuote quote;
  @override
  Future<MarketQuote> fetch(TradeSymbol symbol) async => quote;
}

class _DelayedQuoteProvider implements PaperQuoteProvider {
  final response = Completer<MarketQuote>();

  @override
  Future<MarketQuote> fetch(TradeSymbol symbol) => response.future;
}

class _Store implements PaperJournalStore {
  final rows = <LedgerEntry>[];
  @override
  Future<List<LedgerEntry>> list(String key) async => rows
      .where((e) => e.accountKey == key).toList(growable: false);
  @override
  Future<void> add(LedgerEntry entry) async {
    rows.add(LedgerEntry(id: rows.length + 1,
      accountKey: entry.accountKey, kind: entry.kind,
      timestampMs: entry.timestampMs, openedAtMs: entry.openedAtMs,
      symbol: entry.symbol, side: entry.side, quantity: entry.quantity,
      entryPrice: entry.entryPrice, exitPrice: entry.exitPrice,
      amount: entry.amount, fee: entry.fee));
  }
  @override
  Future<void> closeTrade(String key, int id,
      {required double exitPrice, required int timestampMs}) async {
    final index = rows.indexWhere((e) => e.accountKey == key &&
        e.id == id && e.kind == LedgerKind.openTrade && e.timestampMs <= timestampMs);
    if (index < 0) throw StateError('not open');
    final old = rows[index];
    rows[index] = LedgerEntry(id: old.id,
      accountKey: old.accountKey, kind: LedgerKind.closedTrade,
      symbol: old.symbol, side: old.side, quantity: old.quantity,
      entryPrice: old.entryPrice, exitPrice: exitPrice,
      timestampMs: timestampMs, openedAtMs: old.openedAtMs);
  }
  @override
  Future<void> delete(String key, int id) async {
    rows.removeWhere((e) => e.accountKey == key && e.id == id);
  }
  @override
  Future<void> close() async {}
}

void main() {
  const symbol = TradeSymbol('XAUUSD', 'الذهب', InstrumentKind.gold, TradeSource.ctrader);
  const time = 1790000000000;
  MarketQuote quote(double bid, double ask,
      {int timestamp = time, TradeSource source = TradeSource.ctrader}) =>
      MarketQuote(symbol: 'XAUUSD', source: source,
        bid: bid, ask: ask, timestampMs: timestamp);

  test('paper BUY uses ask and closes at bid, never broker execution', () async {
    var now = time;
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _QuoteProvider(quote(2000, 2000.4));
    final service = PaperTradeService(quotes: feed, journal: journal,
      nowMs: () => now);
    final prepared = await service.prepare(symbol);
    await service.open(symbol: symbol, side: PaperSide.buy,
      units: 2, prepared: prepared);
    final open = journal.entries.single;
    expect(open.kind, LedgerKind.openTrade);
    expect(open.entryPrice, 2000.4);
    expect(calculateLedgerReport(journal.entries).netProfit, 0);
    now += 10000;
    feed.quote = quote(2010, 2010.3, timestamp: now);
    final closing = await service.prepare(symbol);
    await service.close(position: open, prepared: closing);
    final closed = journal.entries.single;
    expect(closed.kind, LedgerKind.closedTrade);
    expect(closed.exitPrice, 2010);
    expect(closed.realizedPnl, closeTo(19.2, .00001));
  });

  test('paper SELL opens at bid and closes at ask', () async {
    var now = time;
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _QuoteProvider(quote(2000, 2000.4));
    final service = PaperTradeService(quotes: feed, journal: journal,
      nowMs: () => now);
    await service.open(symbol: symbol, side: PaperSide.sell,
      units: 1, prepared: await service.prepare(symbol));
    final open = journal.entries.single;
    expect(open.entryPrice, 2000);
    now += 10000;
    feed.quote = quote(1990, 1990.3, timestamp: now);
    await service.close(position: open, prepared: await service.prepare(symbol));
    expect(journal.entries.single.realizedPnl, closeTo(9.7, .00001));
  });

  test('stale quote and account switch never write a paper trade', () async {
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _QuoteProvider(quote(2000, 2000.2, timestamp: time - 91000));
    final service = PaperTradeService(quotes: feed, journal: journal,
      nowMs: () => time);
    await expectLater(service.prepare(symbol), throwsA(isA<MarketDataException>()));
    feed.quote = quote(2000, 2000.2);
    final prepared = await service.prepare(symbol);
    await journal.useAccount('12');
    await expectLater(service.open(symbol: symbol, side: PaperSide.buy,
      units: 1, prepared: prepared), throwsStateError);
    expect(journal.entries, isEmpty);
  });

  test('refuses a source that does not match the selected symbol', () async {
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _QuoteProvider(quote(2000, 2000.4, source: TradeSource.binance));
    final service = PaperTradeService(quotes: feed, journal: journal,
      nowMs: () => time);
    await expectLater(service.prepare(symbol), throwsA(isA<MarketDataException>()));
    expect(journal.entries, isEmpty);
  });

  test('quote expires while user confirms an order', () async {
    var now = time;
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final service = PaperTradeService(
      quotes: _QuoteProvider(quote(2000, 2000.4)), journal: journal,
      nowMs: () => now);
    final prepared = await service.prepare(symbol);
    now += 61000;
    await expectLater(service.open(symbol: symbol, side: PaperSide.buy,
      units: 1, prepared: prepared), throwsStateError);
    expect(journal.entries, isEmpty);
  });

  test('a closed position cannot be closed twice', () async {
    var now = time;
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _QuoteProvider(quote(2000, 2000.4));
    final service = PaperTradeService(quotes: feed, journal: journal,
      nowMs: () => now);
    await service.open(symbol: symbol, side: PaperSide.buy,
      units: 1, prepared: await service.prepare(symbol));
    final open = journal.entries.single;
    now += 1000;
    feed.quote = quote(2001, 2001.2, timestamp: now);
    final prepared = await service.prepare(symbol);
    await service.close(position: open, prepared: prepared);
    await expectLater(service.close(position: open, prepared: prepared),
      throwsStateError);
    expect(journal.entries.single.kind, LedgerKind.closedTrade);
  });

  test('A to B to A account switch invalidates a still-fresh order quote',
      () async {
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _QuoteProvider(quote(2000, 2000.4));
    final service = PaperTradeService(
        quotes: feed, journal: journal, nowMs: () => time);
    final prepared = await service.prepare(symbol);

    await journal.useAccount('12');
    await journal.useAccount('11');
    expect(prepared.accountKey, journal.accountKey,
        reason: 'The literal account key has returned to its old value');
    expect(prepared.accountSessionRevision,
        isNot(journal.accountSessionRevision));
    await expectLater(
      service.open(symbol: symbol, side: PaperSide.buy,
        units: 1, prepared: prepared),
      throwsStateError,
    );
    expect(journal.entries, isEmpty,
        reason: 'An earlier broker session cannot create a new paper trade');
    final latest = await service.prepare(symbol);
    await service.open(symbol: symbol, side: PaperSide.buy,
      units: 1, prepared: latest);
    expect(journal.entries, hasLength(1));
  });

  test('A to B to A switch invalidates a pending close confirmation',
      () async {
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final service = PaperTradeService(
        quotes: _QuoteProvider(quote(2000, 2000.3)),
        journal: journal, nowMs: () => time);
    await service.open(symbol: symbol, side: PaperSide.buy,
        units: 1, prepared: await service.prepare(symbol));
    final open = journal.entries.single;
    final pendingExit = await service.prepare(symbol);
    await journal.useAccount('12');
    await journal.useAccount('11');
    await expectLater(service.close(position: open,
      prepared: pendingExit), throwsStateError);
    expect(journal.entries.single.kind, LedgerKind.openTrade,
        reason: 'An obsolete account session must not close a position');
  });

  test('account switch during quote fetch rejects even if user returns to A',
      () async {
    final journal = PaperJournalController(store: _Store());
    addTearDown(journal.dispose);
    await journal.useAccount('11');
    final feed = _DelayedQuoteProvider();
    final service = PaperTradeService(
        quotes: feed, journal: journal, nowMs: () => time);
    final inFlight = service.prepare(symbol);
    final expectRejected =
        expectLater(inFlight, throwsA(isA<MarketDataException>()));
    await journal.useAccount('12');
    await journal.useAccount('11');
    feed.response.complete(quote(2000, 2000.3));
    await expectRejected;
    expect(journal.entries, isEmpty);
  });

}
