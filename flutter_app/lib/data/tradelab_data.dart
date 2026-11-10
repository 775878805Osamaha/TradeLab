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
