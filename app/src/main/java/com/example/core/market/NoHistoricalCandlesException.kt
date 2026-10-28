package com.example.core.market

/** A verified empty response is distinct from an outage or malformed OHLC. */
class NoHistoricalCandlesException(symbol: String) : java.io.IOException(
    "No verified historical candles for $symbol"
)
