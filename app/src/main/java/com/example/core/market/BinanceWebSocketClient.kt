package com.example.core.market

import com.example.core.model.ProviderConnectionStatus
import com.example.core.model.Tick
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.random.Random

class BinanceWebSocketClient(
    private val onTickReceived: (Tick) -> Unit,
    private val onRawMessage: ((String) -> Unit)? = null,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
) {

    private val _connectionStatus = MutableStateFlow(ProviderConnectionStatus.DISCONNECTED)
    val connectionStatus: StateFlow<ProviderConnectionStatus> = _connectionStatus.asStateFlow()

    private val _reconnectAttempts = MutableStateFlow(0)
    val reconnectAttempts: StateFlow<Int> = _reconnectAttempts.asStateFlow()

    private val _lastMessageTime = MutableStateFlow(0L)
    val lastMessageTime: StateFlow<Long> = _lastMessageTime.asStateFlow()

    private val _latencyMs = MutableStateFlow(0L)
    val latencyMs: StateFlow<Long> = _latencyMs.asStateFlow()

    private var webSocket: WebSocket? = null
    private var isExplicitlyStopped = false
    private var reconnectJob: Job? = null
    private var pingJob: Job? = null

    private val okHttpClient = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    fun start() {
        isExplicitlyStopped = false
        connect()
    }

    fun stop() {
        isExplicitlyStopped = true
        reconnectJob?.cancel()
        pingJob?.cancel()
        webSocket?.close(1000, "Normal closure")
        webSocket = null
        _connectionStatus.value = ProviderConnectionStatus.DISCONNECTED
    }

    private fun connect() {
        if (isExplicitlyStopped) return

        _connectionStatus.value = if (_reconnectAttempts.value > 0) ProviderConnectionStatus.RECONNECTING else ProviderConnectionStatus.CONNECTING

        val request = Request.Builder()
            .url("wss://stream.binance.com:9443/ws/btcusdt@bookTicker/ethusdt@bookTicker")
            .build()

        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (isExplicitlyStopped) return
                _connectionStatus.value = ProviderConnectionStatus.CONNECTED
                _reconnectAttempts.value = 0
                startHeartbeat(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (isExplicitlyStopped) return
                val now = System.currentTimeMillis()
                _lastMessageTime.value = now
                onRawMessage?.invoke(text)

                try {
                    val json = JSONObject(text)
                    if (json.has("s") && json.has("b") && json.has("a")) {
                        val sym = json.getString("s")
                        val bid = json.getDouble("b")
                        val ask = json.getDouble("a")
                        val tick = Tick(
                            symbol = sym,
                            bid = bid,
                            ask = ask,
                            last = (bid + ask) / 2.0,
                            timestamp = now,
                            source = "BINANCE_WEBSOCKET",
                            volume = 1.0
                        )
                        if (DataIntegrityValidator.validateTick(tick).isValid) {
                            onTickReceived(tick)
                            _connectionStatus.value = ProviderConnectionStatus.CONNECTED
                        }
                    }
                } catch (e: Exception) {
                    // Silently ignore malformed packet
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (isExplicitlyStopped) return
                _connectionStatus.value = ProviderConnectionStatus.DEGRADED
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (isExplicitlyStopped) return
                scheduleReconnect()
            }
        })
    }

    private fun startHeartbeat(ws: WebSocket) {
        pingJob?.cancel()
        pingJob = scope.launch {
            while (isActive && !isExplicitlyStopped) {
                delay(15000)
                try {
                    val pingSentTime = System.currentTimeMillis()
                    ws.send("{\"method\":\"PING\"}")
                    _latencyMs.value = System.currentTimeMillis() - pingSentTime
                } catch (e: Exception) {
                    // Ignored
                }
            }
        }
    }

    private fun scheduleReconnect() {
        if (isExplicitlyStopped) return

        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            _reconnectAttempts.value += 1
            _connectionStatus.value = ProviderConnectionStatus.RECONNECTING

            // Exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s + jitter
            val attempt = _reconnectAttempts.value
            val baseDelay = min(30000L, (1000L * (1L shl min(attempt, 5))))
            val jitter = Random.nextLong(0, 500)
            val totalDelay = baseDelay + jitter

            delay(totalDelay)
            if (!isExplicitlyStopped) {
                connect()
            }
        }
    }
}
