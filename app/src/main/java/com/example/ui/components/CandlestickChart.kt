package com.example.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.indicators.BollingerBandsResult
import com.example.core.indicators.MacdResult
import com.example.core.model.*
import com.example.feature.chart.model.*
import com.example.ui.components.chart.ChartDrawingsRenderer
import com.example.ui.components.chart.ChartIndicatorsRenderer
import com.example.ui.components.chart.ChartOverlays
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

enum class ChartDisplayStyle(val label: String) {
    CANDLES("شموع"),
    LINE("خطي"),
    HEIKIN_ASHI("هيكين آشي")
}

@Composable
fun CandlestickChart(
    candles: List<Candle>,
    modifier: Modifier = Modifier,
    latestTick: Tick? = null,
    openPositions: List<Position> = emptyList(),
    pendingOrders: List<Order> = emptyList(),
    historicalTrades: List<TradeJournalEntry> = emptyList(),
    activeDrawingTool: DrawingTool = DrawingTool.NONE,
    drawings: List<ChartDrawing> = emptyList(),
    indicatorSettings: IndicatorSettings = IndicatorSettings(),
    smaValues: List<Double?> = emptyList(),
    emaValues: List<Double?> = emptyList(),
    bollingerValues: List<BollingerBandsResult?> = emptyList(),
    vwapValues: List<Double> = emptyList(),
    rsiValues: List<Double?> = emptyList(),
    macdValues: List<MacdResult?> = emptyList(),
    atrValues: List<Double?> = emptyList(),
    isCrosshairActive: Boolean = false,
    isVolumeVisible: Boolean = true,
    resetViewTrigger: Long = 0L,
    displayStyle: ChartDisplayStyle = ChartDisplayStyle.CANDLES,
    onAddDrawing: ((ChartDrawing) -> Unit)? = null,
    onSelectTrade: ((TradeJournalEntry) -> Unit)? = null,
    onRequestOlderHistory: (() -> Unit)? = null,
    isLoadingOlderHistory: Boolean = false
) {
    if (candles.isEmpty()) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .testTag("candlestick_chart_empty"),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "جاري تحميل بيانات الشارت...",
                color = TradingTextSecondary,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        return
    }

    // Convert only when candle data or display style changes, not on each
    // canvas redraw caused by zoom, pan, crosshair or other UI gestures.
    val heikinAshiCandles = remember(candles, displayStyle) {
        if (displayStyle != ChartDisplayStyle.HEIKIN_ASHI) emptyList()
        else {
            val converted = ArrayList<Candle>(candles.size)
            candles.forEachIndexed { index, raw ->
                val haClose = (raw.open + raw.high + raw.low + raw.close) / 4.0
                val haOpen = if (index == 0) (raw.open + raw.close) / 2.0
                    else (converted.last().open + converted.last().close) / 2.0
                converted.add(raw.copy(
                    open = haOpen, close = haClose,
                    high = maxOf(raw.high, haOpen, haClose),
                    low = minOf(raw.low, haOpen, haClose)
                ))
            }
            converted
        }
    }

    // Viewport State
    var candleWidthPx by remember { mutableFloatStateOf(12f) }
    var scrollOffsetPx by remember { mutableFloatStateOf(0f) }
    var manualPriceScale by remember { mutableFloatStateOf(1f) }
    // Vertical viewport translation in screen pixels, independent of candle zoom.
    var pricePanPx by remember { mutableFloatStateOf(0f) }
    var crosshairOffset by remember { mutableStateOf<Offset?>(null) }
    var inspectedCandle by remember { mutableStateOf<Candle?>(null) }

    val transformRef = remember { arrayOfNulls<ChartTransform>(1) }
    var dragStartedInPlot by remember { mutableStateOf(false) }
    // Keep the most recent coordinate transform available while Replay appends
    // candles. The Canvas refreshes it on redraw; clearing it on every new
    // candle makes onDragStart reject touches until that redraw completes.
    // Explicit reset-view still clears the transform below.
    // Avoid creating a new visible OHLC list or scanning the entire history
    // during pan/zoom; range queries are served by the immutable price index.
    val priceRangeIndex = remember(candles) { ChartPriceRangeIndex(candles) }

    // Drawing Interaction State
    var drawingStartOffset by remember { mutableStateOf<Offset?>(null) }
    var drawingCurrentOffset by remember { mutableStateOf<Offset?>(null) }

    // Reset View trigger
    LaunchedEffect(resetViewTrigger) {
        if (resetViewTrigger > 0L) {
            scrollOffsetPx = 0f
            candleWidthPx = 12f
            manualPriceScale = 1f
            pricePanPx = 0f
            crosshairOffset = null
            inspectedCandle = null
            transformRef[0] = null
        }
    }

        // Show the inspected candle only while crosshair mode is enabled.
        // Avoid stale OHLC data lingering after the user exits inspection.
        LaunchedEffect(isCrosshairActive) {
            if (!isCrosshairActive) {
                crosshairOffset = null
                inspectedCandle = null
            }
        }

    // Switching drawing tools must cancel unfinished drag previews.
    LaunchedEffect(activeDrawingTool) {
        drawingStartOffset = null
        drawingCurrentOffset = null
    }

    val transformableState = rememberTransformableState { zoomChange, panChange, _ ->
        if (zoomChange.isFinite() && zoomChange > 0f) {
            candleWidthPx = (candleWidthPx * zoomChange).coerceIn(6f, 80f)
        }
        // Transformable consumes multi-touch transforms; detectDragGestures
        // below handles one-finger dragging. Apply two-finger translation as
        // well so the chart does not freeze while users pinch and reposition.
        if (panChange.x.isFinite() && panChange.x != 0f) {
            scrollOffsetPx = ChartNavigation.drag(scrollOffsetPx, panChange.x)
        }
        if (panChange.y.isFinite() && panChange.y != 0f) {
            pricePanPx = (pricePanPx + panChange.y).coerceIn(-6000f, 6000f)
        }
    }

    val timeFormat = remember { SimpleDateFormat("HH:mm", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") } }
    val dateTimeFormat = remember { SimpleDateFormat("MM/dd HH:mm", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") } }
    // Paint instances are reused across redraws instead of allocated once per
    // grid label / timestamp on every pinch, drag or replay tick.
    val priceAxisPaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#9CA3AF")
            textSize = 23f
            isFakeBoldText = false
        }
    }
    // Reuse the axis paint during crosshair drags; no allocation per frame.
    val crosshairAxisPaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = 20f
        }
    }
    val crosshairBadgePaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#334155")
        }
    }
    val timeAxisPaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#6B7280")
            textSize = 21f
            textAlign = android.graphics.Paint.Align.CENTER
        }
    }

    // Wait for the real measured width before applying initial candle fit.
    // A guessed 600px width can mis-size early Replay candles on narrow phones.
    var chartViewportWidthPx by remember { mutableFloatStateOf(0f) }
    // Trigger historical backfill near the oldest visible candle. Keep the
    // gesture callback fresh without restarting the active pointer detector.
    val requestOlderHistory by rememberUpdatedState(onRequestOlderHistory)
    val loadingOlderHistory by rememberUpdatedState(isLoadingOlderHistory)
    var lastBackfillOldestTime by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(candles.firstOrNull()?.openTime, scrollOffsetPx, chartViewportWidthPx,
        candleWidthPx, isLoadingOlderHistory) {
        val oldest = candles.firstOrNull()?.openTime ?: return@LaunchedEffect
        if (requestOlderHistory == null || loadingOlderHistory || candles.size >= 20_000 ||
            chartViewportWidthPx <= 1f) return@LaunchedEffect
        val threshold = (candles.size * candleWidthPx - chartViewportWidthPx -
            candleWidthPx * 30f).coerceAtLeast(0f)
        if (scrollOffsetPx > 0f && scrollOffsetPx >= threshold && lastBackfillOldestTime != oldest) {
            lastBackfillOldestTime = oldest
            requestOlderHistory?.invoke()
        }
    }
    // Scroll is measured from the newest (rightmost) candle. Prepending
    // history on the left does not change the position of existing bars.
    // Keep the offset unchanged; compensating here would cause a chart jump.
    // Early Replay can have only a few revealed bars. The fixed 12px default
    // leaves most of the canvas empty on phones; fit those bars on first load.
    // Never override user zoom after the initial fit.
    var initialCandleFitApplied by remember { mutableStateOf(false) }
    // Reset is a user-requested fresh fit, not merely a return to 12px bars.
    // This effect is declared after the state to avoid referencing an
    // uninitialized local Compose state holder.
    LaunchedEffect(resetViewTrigger) {
        if (resetViewTrigger > 0L) initialCandleFitApplied = false
    }
    LaunchedEffect(candles.size, chartViewportWidthPx) {
        if (!initialCandleFitApplied && candles.isNotEmpty() && chartViewportWidthPx > 1f) {
            if (candles.size <= 40) {
                candleWidthPx = (chartViewportWidthPx * 0.76f / candles.size)
                    .coerceIn(12f, 38f)
            }
            initialCandleFitApplied = true
        }
    }
    Box(modifier = modifier.onSizeChanged { chartViewportWidthPx = (it.width - 122f).coerceAtLeast(1f) }) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .testTag("candlestick_canvas")
                .transformable(state = transformableState, enabled = activeDrawingTool == DrawingTool.NONE && !isCrosshairActive)
                // Keep gesture recognition alive while Replay reveals each new candle.
                // Recreating pointerInput on every candle update cancels active drags.
                .pointerInput(activeDrawingTool, isCrosshairActive) {
                    detectDragGestures(
                        onDragStart = { offset ->
                            val transform = transformRef[0]
                            dragStartedInPlot = transform != null &&
                                offset.x in 0f..transform.chartWidth &&
                                offset.y in 0f..transform.chartHeight
                            if (!dragStartedInPlot) return@detectDragGestures
                            if (activeDrawingTool != DrawingTool.NONE) {
                                drawingStartOffset = offset
                                drawingCurrentOffset = offset
                            } else if (isCrosshairActive) {
                                crosshairOffset = offset
                            }
                        },
                        onDrag = { change, dragAmount ->
                            if (!dragStartedInPlot) return@detectDragGestures
                            // Only consume drags after the gesture has started inside the plot.
                            change.consume()
                            if (activeDrawingTool != DrawingTool.NONE) {
                                drawingCurrentOffset = change.position
                            } else if (isCrosshairActive) {
                                val transform = transformRef[0]
                                if (transform != null) {
                                    crosshairOffset = Offset(
                                        change.position.x.coerceIn(0f, transform.chartWidth),
                                        change.position.y.coerceIn(0f, transform.chartHeight)
                                    )
                                }
                            } else {
                                scrollOffsetPx = ChartNavigation.drag(scrollOffsetPx, dragAmount.x)
                                // Let a single diagonal gesture pan both time and price axes.
                                // The visual direction follows the finger; reset view restores auto-fit.
                                pricePanPx = (pricePanPx + dragAmount.y).coerceIn(-6000f, 6000f)
                            }
                        },
                        onDragEnd = {
                            if (dragStartedInPlot && activeDrawingTool != DrawingTool.NONE && drawingStartOffset != null && drawingCurrentOffset != null) {
                                val start = drawingStartOffset!!
                                val end = drawingCurrentOffset!!
                                val transform = transformRef[0]
                                val distance = (end - start).getDistance()
                                if (transform != null && onAddDrawing != null && distance >= 10f &&
                                    activeDrawingTool != DrawingTool.HORIZONTAL_LINE &&
                                    activeDrawingTool != DrawingTool.VERTICAL_LINE) {
                                    onAddDrawing(
                                        ChartDrawing(
                                            tool = activeDrawingTool,
                                            symbol = "",
                                            timeframe = "",
                                            startTime = transform.xToTime(start.x),
                                            startPrice = transform.yToPrice(start.y),
                                            endTime = transform.xToTime(end.x),
                                            endPrice = transform.yToPrice(end.y)
                                        )
                                    )
                                }
                                drawingStartOffset = null
                                drawingCurrentOffset = null
                            }
                            dragStartedInPlot = false
                        },
                        onDragCancel = {
                            drawingStartOffset = null
                            drawingCurrentOffset = null
                            dragStartedInPlot = false
                        }
                    )
                }
                .pointerInput(candles, activeDrawingTool, isCrosshairActive) {
                    detectTapGestures(
                        onTap = { offset ->
                            val transform = transformRef[0]
                            val insidePlot = transform != null &&
                                offset.x in 0f..transform.chartWidth &&
                                offset.y in 0f..transform.chartHeight
                            if (insidePlot && transform != null && onAddDrawing != null &&
                                (activeDrawingTool == DrawingTool.HORIZONTAL_LINE ||
                                 activeDrawingTool == DrawingTool.VERTICAL_LINE)) {
                                onAddDrawing(
                                    ChartDrawing(
                                        tool = activeDrawingTool,
                                        symbol = "",
                                        timeframe = "",
                                        startTime = transform.xToTime(offset.x),
                                        startPrice = transform.yToPrice(offset.y)
                                    )
                                )
                            } else if (isCrosshairActive && insidePlot) {
                                crosshairOffset = offset
                            }
                        }
                    )
                }
        ) {
            val width = size.width
            val height = size.height
            // Reserve sufficient width for large formatted prices (e.g. 81,500.00).
            val rightAxisWidth = 122f
            val chartWidth = (width - rightAxisWidth).coerceAtLeast(1f)

            // Subpanel height split
            val hasSubpanel = indicatorSettings.hasSubpanelIndicators
            val subpanelHeight = if (hasSubpanel) height * 0.22f else 0f
            val volumeHeight = if (isVolumeVisible) height * 0.14f else 0f
            val mainChartHeight = (height - subpanelHeight - volumeHeight).coerceAtLeast(10f)

            // Shared, independently testable viewport calculation.
            val viewport = ChartViewport.window(
                candleCount = candles.size,
                chartWidthPx = chartWidth,
                candleWidthPx = candleWidthPx,
                requestedOffsetPx = scrollOffsetPx
            )
            if (scrollOffsetPx != viewport.clampedOffsetPx) {
                scrollOffsetPx = viewport.clampedOffsetPx
            }
            val fractionalScrollPx = viewport.fractionalScrollPx
            val startIndex = viewport.startIndex
            val endIndex = viewport.endIndex
            val visibleCandles = candles.subList(startIndex, endIndex)

            if (visibleCandles.isEmpty()) return@Canvas

            // Calculate min & max prices for visible range
            val priceRange = priceRangeIndex.query(startIndex, endIndex)
            var minP = priceRange.first
            var maxP = priceRange.second
            if (minP == maxP) {
                minP *= 0.99
                maxP *= 1.01
            }
            // Add 3% vertical padding
            val pPadding = (maxP - minP) * 0.055
            val autoMin = minP - pPadding
            val autoMax = maxP + pPadding
            val midpoint = (autoMin + autoMax) / 2.0
            val halfRange = ((autoMax - autoMin) / 2.0) * manualPriceScale
            val pricePanDelta = (pricePanPx / mainChartHeight.coerceAtLeast(1f)) * (halfRange * 2.0)
            val paddedMin = midpoint - halfRange + pricePanDelta
            val paddedMax = midpoint + halfRange + pricePanDelta

            val transform = ChartTransform(
                visibleCandles = visibleCandles,
                minPrice = paddedMin,
                maxPrice = paddedMax,
                chartWidth = chartWidth,
                chartHeight = mainChartHeight,
                candleWidthPx = candleWidthPx,
                rightAxisWidth = rightAxisWidth,
                fractionalScrollPx = fractionalScrollPx
            )

            transformRef[0] = transform

            // Update inspected candle for Crosshair HUD
            crosshairOffset?.let { off ->
                val idx = transform.xToCandleIndex(off.x)
                if (idx in visibleCandles.indices) {
                    inspectedCandle = visibleCandles[idx]
                }
            }

            // Pure price-axis engine keeps levels consistent across redraws and zooms.
            val priceScale = ChartPriceAxis.calculate(paddedMin, paddedMax, mainChartHeight)
            for (tick in priceScale.ticks) {
                val y = tick.fractionFromTop * mainChartHeight
                drawLine(
                    color = TradingBorder.copy(alpha = 0.3f),
                    start = Offset(0f, y),
                    end = Offset(chartWidth, y),
                    strokeWidth = 1f
                )
                drawContext.canvas.nativeCanvas.apply {
                    val labelY = (y + priceAxisPaint.textSize * 0.35f)
                        .coerceIn(priceAxisPaint.textSize, height - 8f)
                    val availableLabelWidth = (rightAxisWidth - 14f).coerceAtLeast(20f)
                    val measuredWidth = priceAxisPaint.measureText(tick.label)
                    val originalSize = priceAxisPaint.textSize
                    if (measuredWidth > availableLabelWidth) {
                        priceAxisPaint.textSize = (originalSize * availableLabelWidth / measuredWidth)
                            .coerceAtLeast(14f)
                    }
                    drawText(tick.label, chartWidth + 7f, labelY, priceAxisPaint)
                    priceAxisPaint.textSize = originalSize
                }
            }

            // Display-only Heikin-Ashi; raw market candles still drive trading.
            val displayedCandles = if (displayStyle == ChartDisplayStyle.HEIKIN_ASHI)
                heikinAshiCandles.subList(startIndex, endIndex)
            else visibleCandles

            // 1. Draw Visible OHLC Candlesticks
            val bodyWidth = (candleWidthPx * 0.78f).coerceAtLeast(1.5f)
            if (displayStyle == ChartDisplayStyle.LINE) {
                val linePath = Path()
                visibleCandles.forEachIndexed { i, candle ->
                    val x = transform.candleIndexToX(i)
                    val y = transform.priceToY(candle.close)
                    if (i == 0) linePath.moveTo(x, y) else linePath.lineTo(x, y)
                }
                drawPath(linePath, color = TradingAccentLight, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.5f))
            } else displayedCandles.forEachIndexed { i, c ->
                val x = transform.candleIndexToX(i)
                val openY = transform.priceToY(c.open)
                val closeY = transform.priceToY(c.close)
                val highY = transform.priceToY(c.high)
                val lowY = transform.priceToY(c.low)

                val isBullish = c.close >= c.open
                val candleColor = if (isBullish) TradingPositive else TradingNegative

                // Wick line
                drawLine(
                    color = candleColor,
                    start = Offset(x, highY),
                    end = Offset(x, lowY),
                    strokeWidth = 1.4f
                )

                // Body rect
                val bodyTop = min(openY, closeY)
                val bodyHeight = abs(closeY - openY).coerceAtLeast(1.5f)
                drawRect(
                    color = candleColor,
                    topLeft = Offset(x - (bodyWidth / 2f), bodyTop),
                    size = Size(bodyWidth, bodyHeight)
                )


            }

            // Adaptive, measured time labels: avoid overlapping text and clipping.
            // Show a full date at day boundaries; otherwise keep intraday labels short.
            var lastTimeLabelRight = -Float.MAX_VALUE
            var lastDisplayedDay = -1L
            visibleCandles.forEachIndexed { i, c ->
                val x = transform.candleIndexToX(i)
                val day = ChartTimeAxis.dayKey(c.openTime)
                val label = ChartTimeAxis.label(
                    c.openTime,
                    if (lastDisplayedDay == day) c.openTime else null
                )
                val textWidth = timeAxisPaint.measureText(label)
                val left = x - textWidth / 2f
                val right = x + textWidth / 2f
                if (ChartTimeAxis.shouldDisplay(left, right, chartWidth, lastTimeLabelRight)) {
                    drawContext.canvas.nativeCanvas.drawText(
                        label, x, height - 8f, timeAxisPaint
                    )
                    lastTimeLabelRight = right
                    lastDisplayedDay = day
                }
            }

            // 2. Draw Volume Bars
            if (isVolumeVisible) {
                val volTop = mainChartHeight
                val maxVol = max(1.0, priceRangeIndex.maxVolume(startIndex, endIndex))
                visibleCandles.forEachIndexed { i, c ->
                    val x = transform.candleIndexToX(i)
                    val volHeight = (c.volume / maxVol).coerceIn(0.0, 1.0).toFloat() * volumeHeight
                    val y = volTop + volumeHeight - volHeight
                    val isBullish = c.close >= c.open
                    val volColor = if (isBullish) TradingPositive.copy(alpha = 0.35f) else TradingNegative.copy(alpha = 0.35f)

                    drawRect(
                        color = volColor,
                        topLeft = Offset(x - (bodyWidth / 2f), y),
                        size = Size(bodyWidth, volHeight)
                    )
                }
            }

            // Indicator series are indexed by the FULL candle history. Slice them
            // to the visible viewport before plotting, otherwise the first EMA/RSI
            // values are incorrectly drawn over the latest candles after panning.
            // Reject incomplete series rather than silently shifting their origin.
            fun <T> visibleIndicator(series: List<T>): List<T> =
                if (series.size == candles.size && endIndex <= series.size)
                    series.subList(startIndex, endIndex)
                else emptyList()

            // 3. Draw Subpanel (RSI / MACD / ATR)
            if (hasSubpanel) {
                val subpanelTop = mainChartHeight + volumeHeight
                ChartIndicatorsRenderer.drawSubpanel(
                    scope = this,
                    panelTop = subpanelTop,
                    panelHeight = subpanelHeight,
                    chartWidth = chartWidth,
                    transform = transform,
                    settings = indicatorSettings,
                    rsiValues = visibleIndicator(rsiValues),
                    macdValues = visibleIndicator(macdValues),
                    atrValues = atrValues
                )
            }

            // 4. Draw Main Indicators (SMA, EMA, Bollinger, VWAP)
            ChartIndicatorsRenderer.drawMainOverlays(
                scope = this,
                transform = transform,
                settings = indicatorSettings,
                smaValues = smaValues,
                emaValues = emaValues,
                bollingerValues = bollingerValues,
                vwapValues = vwapValues
            )

            // 5. Draw Trading Overlays (Positions, Orders, Historical Trades, Price & Spread)
            ChartOverlays.drawPriceAndSpread(
                this, transform, latestTick,
                showHistoricalLastPrice = endIndex == candles.size,
                priceAxisWidth = rightAxisWidth
            )
            ChartOverlays.drawOpenPositions(this, transform, openPositions)
            ChartOverlays.drawPendingOrders(this, transform, pendingOrders)
            ChartOverlays.drawHistoricalTradeMarkers(this, transform, historicalTrades)

            // 6. Draw User Drawings
            ChartDrawingsRenderer.drawDrawings(this, drawings, transform)

            // 7. Active Drawing Preview while dragging
            if (drawingStartOffset != null && drawingCurrentOffset != null && activeDrawingTool != DrawingTool.NONE) {
                val sOff = drawingStartOffset!!
                val cOff = drawingCurrentOffset!!
                val tempDrawing = ChartDrawing(
                    tool = activeDrawingTool,
                    symbol = "",
                    timeframe = "",
                    startTime = transform.xToTime(sOff.x),
                    startPrice = transform.yToPrice(sOff.y),
                    endTime = transform.xToTime(cOff.x),
                    endPrice = transform.yToPrice(cOff.y)
                )
                ChartDrawingsRenderer.drawDrawings(this, listOf(tempDrawing), transform)
            }

            // 8. Crosshair Lines
            crosshairOffset?.let { off ->
                if (off.x in 0f..chartWidth && off.y in 0f..mainChartHeight) {
                    // Vertical line
                    drawLine(
                        color = Color.White.copy(alpha = 0.5f),
                        start = Offset(off.x, 0f),
                        end = Offset(off.x, mainChartHeight),
                        strokeWidth = 1f
                    )
                    // Horizontal line
                    drawLine(
                        color = Color.White.copy(alpha = 0.5f),
                        start = Offset(0f, off.y),
                        end = Offset(chartWidth, off.y),
                        strokeWidth = 1f
                    )
                    // Price tag
                    val pAtY = transform.yToPrice(off.y)
                    drawContext.canvas.nativeCanvas.apply {
                        val p = crosshairAxisPaint
                        val priceLabel = com.example.ui.components.chart.QuotePriceFormatter.price(pAtY)
                        val originalTextSize = p.textSize
                        val availableWidth = (width - chartWidth - 10f).coerceAtLeast(1f)
                        val naturalWidth = p.measureText(priceLabel)
                        if (naturalWidth > 0f) {
                            p.textSize = originalTextSize *
                                (availableWidth / naturalWidth).coerceIn(0.5f, 1f)
                        }
                        if (p.measureText(priceLabel) <= availableWidth) {
                            val labelY = off.y.coerceIn(p.textSize, height - 8f)
                            drawRoundRect(
                                chartWidth, labelY - p.textSize - 3f,
                                width.toFloat(), labelY + 5f,
                                4f, 4f, crosshairBadgePaint
                            )
                            drawText(priceLabel, chartWidth + 5f, labelY, p)
                        }
                        p.textSize = originalTextSize
                    }
                }
            }
        }

        // Chart navigation is gesture-first in the approved full-screen reference.
        // Preserve zoom, centering and reset through existing gesture and header controls;
        // do not overlay the wide legacy button bar on the candle/volume area.
        // Vertical price-axis scaling; reset-view restores automatic fitting.
        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .width(38.dp)
                .fillMaxHeight()
                .testTag("chart_price_axis_scale")
                .pointerInput(Unit) {
                    detectDragGestures { change, dragAmount ->
                        change.consume()
                        val scaleChange = 1f + dragAmount.y / 400f
                        if (scaleChange.isFinite() && scaleChange > 0f) {
                            manualPriceScale = (manualPriceScale * scaleChange).coerceIn(0.25f, 8f)
                        }
                    }
                }
        )

        // Top Floating Crosshair HUD (OHLCV & Spread)
        inspectedCandle?.let { c ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 76.dp, start = 8.dp, end = 8.dp)
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth(0.96f)
                    .testTag("chart_crosshair_ohlcv_hud"),
                shape = RoundedCornerShape(6.dp),
                colors = CardDefaults.cardColors(containerColor = TradingElevated.copy(alpha = 0.9f))
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(5.dp)
                ) {
                    Text("O: " + com.example.ui.components.chart.QuotePriceFormatter.price(c.open), fontSize = 10.sp, color = TradingTextSecondary)
                    Text("H: " + com.example.ui.components.chart.QuotePriceFormatter.price(c.high), fontSize = 10.sp, color = TradingPositive)
                    Text("L: " + com.example.ui.components.chart.QuotePriceFormatter.price(c.low), fontSize = 10.sp, color = TradingNegative)
                    Text("C: " + com.example.ui.components.chart.QuotePriceFormatter.price(c.close), fontSize = 10.sp, color = if (c.close >= c.open) TradingPositive else TradingNegative)
                    Text("V: " + String.format(Locale.US, "%.1f", c.volume), fontSize = 10.sp, color = TradingGold)
                }
            }
        }
    }
}
