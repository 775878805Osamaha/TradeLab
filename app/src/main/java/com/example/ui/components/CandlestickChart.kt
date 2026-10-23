package com.example.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
    onSelectTrade: ((TradeJournalEntry) -> Unit)? = null
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
    var crosshairOffset by remember { mutableStateOf<Offset?>(null) }
    var inspectedCandle by remember { mutableStateOf<Candle?>(null) }

    val transformRef = remember { arrayOfNulls<ChartTransform>(1) }
    LaunchedEffect(candles) { transformRef[0] = null }
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
        candleWidthPx = (candleWidthPx * zoomChange).coerceIn(6f, 80f)
        // Pinch and two-finger pan share this transformable gesture.
        scrollOffsetPx += panChange.x
    }

    val timeFormat = remember { SimpleDateFormat("MM/dd HH:mm", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") } }
    // Paint instances are reused across redraws instead of allocated once per
    // grid label / timestamp on every pinch, drag or replay tick.
    val priceAxisPaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#9CA3AF")
            textSize = 29f
            isFakeBoldText = true
        }
    }
    // Reuse the axis paint during crosshair drags; no allocation per frame.
    val crosshairAxisPaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            textSize = 20f
        }
    }
    val timeAxisPaint = remember {
        android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.parseColor("#6B7280")
            textSize = 25f
            textAlign = android.graphics.Paint.Align.CENTER
        }
    }

    Box(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .testTag("candlestick_canvas")
                .transformable(state = transformableState, enabled = activeDrawingTool == DrawingTool.NONE && !isCrosshairActive)
                .pointerInput(candles, activeDrawingTool, isCrosshairActive) {
                    detectDragGestures(
                        onDragStart = { offset ->
                            if (activeDrawingTool != DrawingTool.NONE) {
                                drawingStartOffset = offset
                                drawingCurrentOffset = offset
                            } else if (isCrosshairActive) {
                                crosshairOffset = offset
                            }
                        },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            if (activeDrawingTool != DrawingTool.NONE) {
                                drawingCurrentOffset = change.position
                            } else if (isCrosshairActive) {
                                crosshairOffset = change.position
                            } else {
                                scrollOffsetPx += dragAmount.x
                            }
                        },
                        onDragEnd = {
                            if (activeDrawingTool != DrawingTool.NONE && drawingStartOffset != null && drawingCurrentOffset != null) {
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
                        },
                        onDragCancel = {
                            drawingStartOffset = null
                            drawingCurrentOffset = null
                        }
                    )
                }
                .pointerInput(candles, activeDrawingTool, isCrosshairActive) {
                    detectTapGestures(
                        onTap = { offset ->
                            val transform = transformRef[0]
                            if (transform != null && onAddDrawing != null &&
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
                            } else if (isCrosshairActive) {
                                crosshairOffset = offset
                            }
                        }
                    )
                }
        ) {
            val width = size.width
            val height = size.height
            // Reserve sufficient width for large formatted prices (e.g. 81,500.00).
            val rightAxisWidth = 146f
            val chartWidth = (width - rightAxisWidth).coerceAtLeast(1f)

            // Subpanel height split
            val hasSubpanel = indicatorSettings.hasSubpanelIndicators
            val subpanelHeight = if (hasSubpanel) height * 0.22f else 0f
            val volumeHeight = if (isVolumeVisible) height * 0.14f else 0f
            val mainChartHeight = (height - subpanelHeight - volumeHeight).coerceAtLeast(10f)

            // Calculate Visible Candle Range from Viewport
            val visibleCount = ((chartWidth / candleWidthPx) + 3).toInt().coerceIn(1, candles.size)
            // Cap historical scroll at the first available candle; keep fractional
            // movement continuous when the viewport contains fewer candles than it can fit.
            val maxScrollOffset = ((candles.size - 1).coerceAtLeast(0).toDouble() * candleWidthPx)
                .coerceAtLeast(0.0).toFloat()
            // A LEFT swipe makes scrollOffsetPx negative and exposes future space
            // on the RIGHT; a RIGHT swipe moves back toward earlier candles.
            val futureSpacePx = chartWidth * 0.70f
            // Negative offsets are future-space: a leftward finger drag must shift candles LEFT.
            // Positive offsets scroll into history: a rightward drag moves candles RIGHT.
            val clampedScroll = scrollOffsetPx.coerceIn(-futureSpacePx, maxScrollOffset)
            // Persist the clamped offset so repeated drags cannot accumulate
            // invisible overscroll and make the chart feel stuck on reversal.
            if (scrollOffsetPx != clampedScroll) scrollOffsetPx = clampedScroll

            val historicalScrollPx = clampedScroll.coerceAtLeast(0f)
            val scrollCandleOffset = (historicalScrollPx / candleWidthPx).toInt()
                .coerceIn(0, (candles.size - visibleCount).coerceAtLeast(0))
            val fractionalScrollPx = if (clampedScroll < 0f) -clampedScroll else -(historicalScrollPx % candleWidthPx)
            val startIndex = (candles.size - visibleCount - scrollCandleOffset).coerceIn(0, candles.size - 1)
            val endIndex = (startIndex + visibleCount).coerceIn(startIndex, candles.size)
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
            val pPadding = (maxP - minP) * 0.03
            val autoMin = minP - pPadding
            val autoMax = maxP + pPadding
            val midpoint = (autoMin + autoMax) / 2.0
            val halfRange = ((autoMax - autoMin) / 2.0) * manualPriceScale
            val paddedMin = midpoint - halfRange
            val paddedMax = midpoint + halfRange

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

            // Use rounded market-price intervals (1/2/5 x power of ten) like trading terminals.
            // Grid labels remain stable and meaningful as the visible price range changes.
            val desiredTickCount = (mainChartHeight / 86f).toInt().coerceIn(4, 16)
            val rawTickStep = ((paddedMax - paddedMin) / desiredTickCount).coerceAtLeast(1e-9)
            val magnitude = Math.pow(10.0, kotlin.math.floor(kotlin.math.log10(rawTickStep)))
            val normalizedStep = rawTickStep / magnitude
            val tickMultiplier = when {
                normalizedStep <= 1.0 -> 1.0
                normalizedStep <= 2.0 -> 2.0
                normalizedStep <= 5.0 -> 5.0
                else -> 10.0
            }
            val priceTickStep = tickMultiplier * magnitude
            val tickDecimals = (-kotlin.math.floor(kotlin.math.log10(priceTickStep))).toInt().coerceIn(0, 6)
            val firstPriceTick = kotlin.math.ceil(paddedMin / priceTickStep) * priceTickStep
            val priceTickCount = kotlin.math.floor(
                ((paddedMax - firstPriceTick) / priceTickStep).coerceAtLeast(0.0) + 1e-8
            ).toInt().coerceIn(0, 40)
            for (step in 0..priceTickCount) {
                val priceVal = firstPriceTick + step * priceTickStep
                val y = ((paddedMax - priceVal) / (paddedMax - paddedMin) * mainChartHeight).toFloat()
                drawLine(
                    color = TradingBorder.copy(alpha = 0.3f),
                    start = Offset(0f, y),
                    end = Offset(chartWidth, y),
                    strokeWidth = 1f
                )
                // Price Axis Label
                drawContext.canvas.nativeCanvas.apply {
                    val labelY = (y + priceAxisPaint.textSize * 0.35f)
                        .coerceIn(priceAxisPaint.textSize, height - 8f)
                    drawText(String.format(Locale.US, "%,." + tickDecimals + "f", priceVal), chartWidth + 7f, labelY, priceAxisPaint)
                }
            }

            // Display-only Heikin-Ashi; raw market candles still drive trading.
            val displayedCandles = if (displayStyle == ChartDisplayStyle.HEIKIN_ASHI)
                heikinAshiCandles.subList(startIndex, endIndex)
            else visibleCandles

            // 1. Draw Visible OHLC Candlesticks
            val bodyWidth = (candleWidthPx * 0.72f).coerceAtLeast(1.5f)
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

            // Render time labels for all display modes, including the line chart.
            // Timestamps are roughly 100px wide at the chosen font size.
            val minimumTimeLabelGap = 170f
            var lastTimeLabelX = -minimumTimeLabelGap
            visibleCandles.forEachIndexed { i, c ->
                val x = transform.candleIndexToX(i)
                if (x >= 75f && x <= chartWidth - 75f && x - lastTimeLabelX >= minimumTimeLabelGap) {
                    drawContext.canvas.nativeCanvas.apply {
                        drawText(timeFormat.format(Date(c.openTime)), x, height - 8f, timeAxisPaint)
                    }
                    lastTimeLabelX = x
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
                    rsiValues = rsiValues,
                    macdValues = macdValues,
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
            ChartOverlays.drawPriceAndSpread(this, transform, latestTick)
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
                        drawText(String.format(Locale.US, "%.2f", pAtY), chartWidth + 6f, off.y + 6f, p)
                    }
                }
            }
        }

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
                        manualPriceScale = (manualPriceScale * (1f + dragAmount.y / 400f))
                            .coerceIn(0.25f, 8f)
                    }
                }
        )

        // Top Floating Crosshair HUD (OHLCV & Spread)
        inspectedCandle?.let { c ->
            Card(
                modifier = Modifier
                    .padding(8.dp)
                    .align(Alignment.TopStart),
                shape = RoundedCornerShape(6.dp),
                colors = CardDefaults.cardColors(containerColor = TradingElevated.copy(alpha = 0.9f))
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("O: " + String.format(Locale.US, "%.2f", c.open), fontSize = 10.sp, color = TradingTextSecondary)
                    Text("H: " + String.format(Locale.US, "%.2f", c.high), fontSize = 10.sp, color = TradingPositive)
                    Text("L: " + String.format(Locale.US, "%.2f", c.low), fontSize = 10.sp, color = TradingNegative)
                    Text("C: " + String.format(Locale.US, "%.2f", c.close), fontSize = 10.sp, color = if (c.close >= c.open) TradingPositive else TradingNegative)
                    Text("V: " + String.format(Locale.US, "%.1f", c.volume), fontSize = 10.sp, color = TradingGold)
                }
            }
        }
    }
}
