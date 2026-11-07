package com.example.feature.chart

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import com.example.core.market.RangeTickDiagnostics
import com.example.core.model.Candle
import com.example.feature.chart.model.RangeHistoryPaging

/**
 * Range charts are expensive to reconstruct from genuine cTrader BID ticks.
 * Keep the completed viewport and its exact broker cutoff in the activity-scoped
 * ChartViewModel, not in the disposable Chart tab composition.
 */
internal data class RangeChartContext(
    val symbol: String,
    val size: Int,
    val accountGeneration: Long,
    val replay: Boolean,
    val replayDatasetId: Long
)

internal data class RangeChartSnapshot(
    val symbol: String,
    val end: Long,
    val size: Int,
    val hours: Int,
    val accountGeneration: Long,
    val replay: Boolean,
    val replayDatasetId: Long,
    val candles: List<Candle>,
    val diagnostics: RangeTickDiagnostics,
    val complete: Boolean,
    val requestGeneration: Int
)

internal object RangeChartRestorationPolicy {
    /** An exact match is necessary: never recycle later Replay bars or a different account. */
    fun canSkipDownload(
        snapshot: RangeChartSnapshot?, context: RangeChartContext,
        cutoff: Long, hours: Int, requestGeneration: Int
    ): Boolean = snapshot != null && snapshot.complete &&
        snapshot.symbol == context.symbol && snapshot.size == context.size &&
        snapshot.accountGeneration == context.accountGeneration &&
        snapshot.replay == context.replay && snapshot.replayDatasetId == context.replayDatasetId &&
        snapshot.end == cutoff && snapshot.hours == hours &&
        snapshot.requestGeneration == requestGeneration
}

/** Compose-observable state whose lifetime matches ChartViewModel, not ChartScreen. */
internal class RangeChartSession {
    val context = mutableStateOf<RangeChartContext?>(null)
    val historyHours = mutableIntStateOf(RangeHistoryPaging.initialWindowHours(1000))
    val historyCapHours = mutableStateOf<Int?>(null)
    val historyManuallyChosen = mutableStateOf(false)
    val historyJumpGeneration = mutableIntStateOf(0)
    val refreshAnchor = mutableLongStateOf(System.currentTimeMillis())
    val replayBackshiftMillis = mutableLongStateOf(0L)
    val snapshot = mutableStateOf<RangeChartSnapshot?>(null)
    val loading = mutableStateOf(false)
    val loadNonce = mutableIntStateOf(0)
    val firstPageMs = mutableStateOf<Long?>(null)
    val fullLoadMs = mutableStateOf<Long?>(null)
    val receivedQuotes = mutableIntStateOf(0)
    val receivedSlices = mutableIntStateOf(0)
    val error = mutableStateOf<String?>(null)

    /** A returning tab is not a new market request; a changed context is. */
    fun alignTo(requested: RangeChartContext, now: Long = System.currentTimeMillis()): Boolean {
        if (context.value == requested) return false
        context.value = requested
        loadNonce.intValue++ // invalidate callbacks from an obsolete instrument/account
        historyHours.intValue = RangeHistoryPaging.initialWindowHours(requested.size)
        historyCapHours.value = null
        historyManuallyChosen.value = false
        historyJumpGeneration.intValue = 0
        refreshAnchor.longValue = now
        replayBackshiftMillis.longValue = 0L
        snapshot.value = null
        loading.value = false
        firstPageMs.value = null
        fullLoadMs.value = null
        receivedQuotes.intValue = 0
        receivedSlices.intValue = 0
        error.value = null
        return true
    }
}
