package com.example.core.market

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow

/** UI consumers need the newest market snapshot, not a backlog of old quotes. */
internal fun <T> latestMarketFlow(): MutableSharedFlow<T> = MutableSharedFlow(
    replay = 1,
    onBufferOverflow = BufferOverflow.DROP_OLDEST
)

internal class QuoteEndpointPreference {
    private val preferred = ConcurrentHashMap<String, String>()
    private val hosts = listOf("api.binance.com", "api1.binance.com", "api2.binance.com",
        "api3.binance.com", "data-api.binance.vision")

    fun orderedHosts(symbol: String): List<String> {
        val first = preferred[symbol] ?: return hosts
        return listOf(first) + hosts.filter { it != first }
    }

    fun recordSuccess(symbol: String, host: String) {
        require(host in hosts)
        preferred[symbol] = host
    }
}
