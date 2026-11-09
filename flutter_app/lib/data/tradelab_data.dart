import 'dart:math' as math;

enum TradeSource { ctrader, binance }

enum InstrumentKind { gold, forex, crypto }

class TradeSymbol {
  const TradeSymbol(this.code, this.title, this.kind, this.source);

  final String code;
  final String title;
  final InstrumentKind kind;
  final TradeSource source;
}

const tradeSymbols = <TradeSymbol>[
  TradeSymbol('XAUUSD', 'الذهب / الدولار', InstrumentKind.gold, TradeSource.ctrader),
  TradeSymbol('EURUSD', 'اليورو / الدولار', InstrumentKind.forex, TradeSource.ctrader),
  TradeSymbol('GBPUSD', 'الجنيه / الدولار', InstrumentKind.forex, TradeSource.ctrader),
  TradeSymbol('USDJPY', 'الدولار / الين', InstrumentKind.forex, TradeSource.ctrader),
  TradeSymbol('BTCUSDT', 'بيتكوين / دولار', InstrumentKind.crypto, TradeSource.binance),
  TradeSymbol('ETHUSDT', 'إيثريوم / دولار', InstrumentKind.crypto, TradeSource.binance),
];

class TradeCandle {
  const TradeCandle(this.open, this.high, this.low, this.close);

  final double open;
  final double high;
  final double low;
  final double close;

  bool get positive => close >= open;
}

/// This fixture is for a VISUAL DESIGN PREVIEW ONLY; never use in broker,
/// Replay, calculations, backtesting or an actual trading account.
List<TradeCandle> previewCandles() {
  final result = <TradeCandle>[];
  var previous = 54.0;
  for (var index = 0; index < 90; index++) {
    final movement = math.sin(index * .69) * 1.12 +
        math.sin(index * .17) * .91 + (index % 9 == 0 ? -1.28 : .18);
    final closing = previous + movement;
    final high = math.max(previous, closing) + .45 + (index % 4) * .16;
    final low = math.min(previous, closing) - .31 - (index % 3) * .22;
    result.add(TradeCandle(previous, high, low, closing));
    previous = closing;
  }
  return result;
}

/// The Flutter migration does not silently replace the native cTrader / Room
/// implementation. Real prices will be supplied through a broker-aware adapter.
abstract interface class TradeLabGateway {
  bool get connected;
  Future<List<TradeCandle>> loadVerifiedHistory({
    required String symbol,
    required String timeframe,
  });
}

class UnconnectedTradeLabGateway implements TradeLabGateway {
  const UnconnectedTradeLabGateway();

  @override
  bool get connected => false;

  @override
  Future<List<TradeCandle>> loadVerifiedHistory({
    required String symbol,
    required String timeframe,
  }) => Future.error(StateError(
        'بيانات السوق الحقيقية غير متاحة في نسخة معاينة Flutter. '
        'يجب ربط واجهة Flutter بخدمات TradeLab الحالية أولاً.',
      ));
}
