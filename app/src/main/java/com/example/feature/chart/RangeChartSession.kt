package com.example.feature.chart

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import com.example.core.market.RangeTickDiagnostics
import com.example.core.model.Candle
import com.example.feature.chart.model.RangeHistoryPaging
import com.example.ui.components.ChartDisplayStyle

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

internal data class RangeChartLoadRequest(
    val context: RangeChartContext,
    val cutoff: Long,
    val hours: Int,
    val requestGeneration: Int
)

/**
 * Queue only the newest pending Replay cutoff. Switching tabs does not
 * terminate the in-flight download or enqueue an identical request again.
 * This class has no Android dependency and can be exercised in JVM tests.
 */
internal class RangeChartRequestQueue {
    var active: RangeChartLoadRequest? = null
        private set
    var pending: RangeChartLoadRequest? = null
        private set

    fun offer(request: RangeChartLoadRequest): Boolean {
        if (active == null) {
            active = request
            return true
        }
        if (active == request) {
            // A rewind to the in-flight cutoff supersedes a later queued one.
            pending = null
            return false
        }
        if (pending == request) return false
        pending = request
        return false
    }

    fun finish(completed: RangeChartLoadRequest): RangeChartLoadRequest? {
        if (active != completed) return null
        active = pending
        pending = null
        return active
    }

    fun invalidate() {
        active = null
        pending = null
    }
}

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
    val requestGeneration: Int,
    val hasIncompleteLastBar: Boolean = false
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

/**
 * Replay is a chart mode, not a disposable Composable's local dialog state.
 * The bottom navigation removes ChartScreen, while ChartViewModel (and the
 * training ReplayViewModel) stay alive in MainActivity. Keeping these flags
 * with that owner prevents a tab return from silently switching to analysis,
 * changing the RangeChartContext and discarding verified broker candles.
 * A fresh activity still begins in analysis mode unless Replay is opened.
 */
internal class ChartReplayPresentation {
    val enabled = mutableStateOf(false)
    val toolbarOpen = mutableStateOf(false)

    fun close() {
        enabled.value = false
        toolbarOpen.value = false
    }
}

/** Persist the user's Range zoom and pan across tab and Canvas re-creation. */
class RangeChartViewport {
    val candleWidthPx = mutableFloatStateOf(12f)
    val scrollOffsetPx = mutableFloatStateOf(0f)
    val manualPriceScale = mutableFloatStateOf(1f)
    val pricePanPx = mutableFloatStateOf(0f)
    val initialFitApplied = mutableStateOf(false)
    val fittedDisplayStyle = mutableStateOf<ChartDisplayStyle?>(null)
    val lastResetTrigger = mutableLongStateOf(0L)
    val lastBackfillOldestTime = mutableStateOf<Long?>(null)
    val lastBackfillScrollOffset = mutableFloatStateOf(0f)

    fun reset() {
        candleWidthPx.floatValue = 12f
        scrollOffsetPx.floatValue = 0f
        manualPriceScale.floatValue = 1f
        pricePanPx.floatValue = 0f
        initialFitApplied.value = false
        fittedDisplayStyle.value = null
        lastResetTrigger.longValue = 0L
        lastBackfillOldestTime.value = null
        lastBackfillScrollOffset.floatValue = 0f
    }
}

/** Compose-observable state whose lifetime matches ChartViewModel, not ChartScreen. */
internal class RangeChartSession {
    val context = mutableStateOf<RangeChartContext?>(null)
    val viewport = RangeChartViewport()
    val historyHours = mutableIntStateOf(RangeHistoryPaging.initialWindowHours(1000))
    val historyCapHours = mutableStateOf<Int?>(null)
    val historyManuallyChosen = mutableStateOf(false)
    val historyJumpGeneration = mutableIntStateOf(0)
    val refreshAnchor = mutableLongStateOf(System.currentTimeMillis())
    val replayBackshiftMillis = mutableLongStateOf(0L)
    val snapshot = mutableStateOf<RangeChartSnapshot?>(null)
    val warmRestored = mutableStateOf(false)
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
        viewport.reset()
        refreshAnchor.longValue = now
        replayBackshiftMillis.longValue = 0L
        snapshot.value = null
        warmRestored.value = false
        loading.value = false
        firstPageMs.value = null
        fullLoadMs.value = null
        receivedQuotes.intValue = 0
        receivedSlices.intValue = 0
        error.value = null
        return true
    }
}
