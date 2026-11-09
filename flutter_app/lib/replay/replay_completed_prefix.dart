import 'dart:math' as math;

import '../data/tradelab_data.dart';

/// Count genuinely completed provider candles visible at the Replay cursor.
///
/// Binance history is already filtered by its exchange close timestamp in
/// MarketApi.binanceCandles. cTrader's latest live candle may be forming, so
/// conservatively hide only that final candle at the live boundary. An
/// earlier Replay cutoff is always historical, regardless of the provider.
int replayCompletedPrefixCount({
  required TradeSource source,
  required int availableBars,
  required int cursor,
}) {
  final visible = math.min(math.max(0, cursor), math.max(0, availableBars));
  if (source == TradeSource.ctrader && visible == availableBars) {
    return math.max(0, visible - 1);
  }
  return visible;
}
