package com.example.feature.chart.history

import com.example.core.market.MarketDataRequestException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLHandshakeException

/** Retry the SAME uncommitted page, never an append or an unverified empty range. */
object ChartHistoryRetry {
    data class Status(val attempt: Int, val maxAttempts: Int, val delayMillis: Long)
    private val waits = longArrayOf(1_000L, 3_000L)

    suspend fun <T> run(
        onRetry: (Status?) -> Unit = {},
        request: suspend () -> T
    ): T {
        var retries = 0
        try {
            while (true) {
                currentCoroutineContext().ensureActive()
                try {
                    return request().also { currentCoroutineContext().ensureActive() }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: IOException) {
                    currentCoroutineContext().ensureActive()
                    if (retries == waits.size || !isTransient(error)) throw error
                    val wait = waits[retries++]
                    onRetry(Status(retries, waits.size, wait))
                    delay(wait)
                }
            }
        } finally {
            if (retries > 0) onRetry(null)
        }
    }

    private fun isTransient(error: IOException): Boolean {
        val causes = generateSequence<Throwable>(error) { it.cause }.take(16).toList()
        if (causes.any { it is CancellationException || it is IllegalArgumentException || it is SSLHandshakeException }) return false
        val statuses = causes.flatMap { cause ->
            Regex("\\bHTTP\\s+(\\d{3})\\b", RegexOption.IGNORE_CASE)
                .findAll(cause.message.orEmpty()).map { it.groupValues[1].toInt() }.toList()
        }
        // A wrapped network error cannot override an explicit auth/quota rejection.
        if (statuses.isNotEmpty()) return statuses.all { it in setOf(408, 500, 502, 503, 504) }
        return causes.any {
            it is SocketTimeoutException || it is ConnectException || it is UnknownHostException ||
                it is NoRouteToHostException || it is SocketException ||
                (it is MarketDataRequestException &&
                    (it.message.orEmpty().contains("network failure", ignoreCase = true) ||
                        it.message.orEmpty().contains("انتهت مهلة")))
        }
    }
}
