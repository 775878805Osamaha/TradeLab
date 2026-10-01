package com.example.core.replay

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Deterministic ReplayClock controlling simulated market time.
 * Speed factor accurately controls candle progression speed:
 * - 0.5x: 2000ms delay per candle
 * - 1.0x: 1000ms delay per candle
 * - 2.0x: 500ms delay per candle
 * - 5.0x: 200ms delay per candle
 * - 10.0x: 100ms delay per candle
 * - 25.0x: 40ms delay per candle
 * - 50.0x: 20ms delay per candle
 * - 100.0x: 10ms delay per candle
 */
class ReplayClock(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
) {
    private val _currentTime = MutableStateFlow(0L)
    val currentTime: StateFlow<Long> = _currentTime.asStateFlow()

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val _speed = MutableStateFlow(1.0f)
    val speed: StateFlow<Float> = _speed.asStateFlow()

    private val _elapsedReplayTime = MutableStateFlow(0L)
    val elapsedReplayTime: StateFlow<Long> = _elapsedReplayTime.asStateFlow()

    private var initialReplayTime: Long = 0L
    private var clockJob: Job? = null

    var onTickStep: (suspend () -> Boolean)? = null

    fun initialize(startTime: Long) {
        pause()
        initialReplayTime = startTime
        _currentTime.value = startTime
        _elapsedReplayTime.value = 0L
    }

    fun updateCurrentTime(time: Long) {
        _currentTime.value = time
        if (initialReplayTime > 0L) {
            _elapsedReplayTime.value = (time - initialReplayTime).coerceAtLeast(0L)
        }
    }

    fun play() {
        if (_isRunning.value) return
        _isRunning.value = true
        startClockLoop()
    }

    fun pause() {
        _isRunning.value = false
        clockJob?.cancel()
        clockJob = null
    }

    fun setSpeed(factor: Float) {
        val validSpeed = factor.coerceIn(0.5f, 100.0f)
        _speed.value = validSpeed
        if (_isRunning.value) {
            pause()
            play()
        }
    }

    private fun startClockLoop() {
        clockJob?.cancel()
        clockJob = scope.launch {
            while (isActive && _isRunning.value) {
                val delayTime = (1000L / _speed.value).toLong().coerceIn(10L, 2000L)
                delay(delayTime)

                val callback = onTickStep
                if (callback != null) {
                    val hasNext = callback.invoke()
                    if (!hasNext) {
                        pause()
                        break
                    }
                }
            }
        }
    }
}
