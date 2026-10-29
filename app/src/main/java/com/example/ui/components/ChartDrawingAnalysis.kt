package com.example.ui.components

import com.example.core.model.Candle
import com.example.feature.chart.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Only fields affecting the result invalidate calculations; color/width edits stay cheap. */
internal data class DrawingAnalysisKey(
    val id: Long, val tool: DrawingTool, val symbol: String, val timeframe: String,
    val startTime: Long, val endTime: Long?
)

internal class ChartDrawingAnalysisRequest(val candles: List<Candle>, drawings: List<ChartDrawing>) {
    val analysisDrawings = drawings.filter { it.tool in setOf(DrawingTool.ANCHORED_VWAP,
        DrawingTool.VOLUME_PROFILE_FIXED, DrawingTool.VOLUME_PROFILE_SESSION) }
    val keys = analysisDrawings.map {
        DrawingAnalysisKey(it.id,it.tool,it.symbol,it.timeframe,it.startTime,it.endTime)
    }
    val isEmpty get() = keys.isEmpty()
    override fun equals(other: Any?): Boolean = other is ChartDrawingAnalysisRequest &&
        candles === other.candles && keys == other.keys
    override fun hashCode(): Int = 31*System.identityHashCode(candles)+keys.hashCode()
}

internal class ChartDrawingAnalysisSnapshot private constructor(
    private val request: ChartDrawingAnalysisRequest,
    val vwaps: Map<Long,List<VwapPoint>>,
    val profiles: Map<Long,List<CandleVolumeProfile.Bin>>
) {
    fun matches(current: ChartDrawingAnalysisRequest) = request == current

    companion object {
        suspend fun prepare(request: ChartDrawingAnalysisRequest): ChartDrawingAnalysisSnapshot {
            if(request.isEmpty) return ChartDrawingAnalysisSnapshot(request,emptyMap(),emptyMap())
            return withContext(Dispatchers.Default) {
                val context=currentCoroutineContext()
                val vwaps=LinkedHashMap<Long,List<VwapPoint>>()
                val profiles=LinkedHashMap<Long,List<CandleVolumeProfile.Bin>>()
                for(drawing in request.analysisDrawings) {
                    context.ensureActive()
                    if(drawing.tool==DrawingTool.ANCHORED_VWAP) {
                        vwaps[drawing.id]=AnchoredVwap.calculate(request.candles,drawing.startTime) { context.ensureActive() }
                    } else {
                        profiles[drawing.id]=CandleVolumeProfile.forDrawing(request.candles,drawing) { context.ensureActive() }
                    }
                }
                context.ensureActive()
                ChartDrawingAnalysisSnapshot(request,vwaps,profiles)
            }
        }
    }
}
