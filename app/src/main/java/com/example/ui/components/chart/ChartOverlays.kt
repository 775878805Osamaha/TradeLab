package com.example.ui.components.chart

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import com.example.core.model.*
import com.example.feature.chart.model.ChartTransform
import com.example.ui.theme.*
import java.util.Locale

object ChartOverlays {
    private val badgeTextPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        textSize = 19f
        typeface = android.graphics.Typeface.create(
            android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD
        )
    }
    private val badgeBackgroundPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.parseColor("#26A69A")
    }


    // ChartTransform clamps offscreen prices to the plot boundary. Skip those
    // levels rather than drawing misleading horizontal lines at the top/bottom.
    private fun isPriceVisible(transform: ChartTransform, price: Double): Boolean =
        price.isFinite() && price in transform.minPrice..transform.maxPrice

    fun drawPriceAndSpread(
        scope: DrawScope,
        transform: ChartTransform,
        latestTick: Tick?,
        showHistoricalLastPrice: Boolean = true,
        priceAxisWidth: Float = 122f
    ) {
        // Only verified ticks provide executable bid/ask; historical candles
        // are displayed as a chart price, never masquerading as live quotes.
        val chartPrice = latestTick?.last?.takeIf { it.isFinite() && it > 0.0 }
            ?: (if (showHistoricalLastPrice)
                transform.visibleCandles.lastOrNull()?.close?.takeIf { it.isFinite() && it > 0.0 }
            else null)
            ?: return
        if (!isPriceVisible(transform, chartPrice)) return
        val y = transform.priceToY(chartPrice)
        scope.drawLine(
            color = TradingPositive.copy(alpha = 0.82f),
            start = Offset(0f, y),
            end = Offset(transform.chartWidth, y),
            strokeWidth = 1.4f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(7f, 5f), 0f)
        )
        // Reference-style green price label anchored to the actual price axis.
        scope.drawContext.canvas.nativeCanvas.apply {
            val label = QuotePriceFormatter.price(chartPrice)
            val textPaint = badgeTextPaint
            val originalSize = textPaint.textSize
            val availableWidth = (scope.size.width - transform.chartWidth)
                .coerceAtMost(priceAxisWidth).coerceAtLeast(1f)
            val measured = textPaint.measureText(label)
            textPaint.textSize = originalSize * ((availableWidth - 10f) / measured).coerceIn(0.5f, 1f)
            val badgeWidth = (textPaint.measureText(label) + 10f).coerceAtMost(availableWidth)
            val badgeFits = textPaint.measureText(label) + 10f <= availableWidth
            val top = (y - 15f).coerceAtLeast(0f)
            val bottom = (y + 15f).coerceAtMost(scope.size.height)
            val background = badgeBackgroundPaint
            if (bottom > top && badgeFits) {
                drawRoundRect(
                    transform.chartWidth,
                    top,
                    transform.chartWidth + badgeWidth,
                    bottom,
                    5f, 5f, background
                )
                drawText(label, transform.chartWidth + 5f,
                    (top + bottom) / 2f + textPaint.textSize * 0.34f, textPaint)
            }
            textPaint.textSize = originalSize
        }
    }

    fun drawOpenPositions(
        scope: DrawScope,
        transform: ChartTransform,
        positions: List<Position>
    ) {
        for (pos in positions) {
            val entryY = transform.priceToY(pos.entryPrice)
            val isBuy = pos.side == PositionSide.BUY
            val lineColor = if (isBuy) TradingPositive else TradingNegative

            // Reference TP/SL risk zones are drawn only for an actual open position.
            // Clip levels to the visible price range; do not fabricate stops or targets.
            val zoneLeft = transform.chartWidth * 0.54f
            val zoneWidth = (transform.chartWidth - zoneLeft).coerceAtLeast(0f)
            fun drawRiskZone(level: Double?, color: Color) {
                if (level == null || !level.isFinite() || !pos.entryPrice.isFinite()) return
                val clippedEntry = pos.entryPrice.coerceIn(transform.minPrice, transform.maxPrice)
                val clippedLevel = level.coerceIn(transform.minPrice, transform.maxPrice)
                val top = minOf(transform.priceToY(clippedEntry), transform.priceToY(clippedLevel))
                val bottom = maxOf(transform.priceToY(clippedEntry), transform.priceToY(clippedLevel))
                if (bottom > top && zoneWidth > 0f) {
                    scope.drawRect(
                        color = color.copy(alpha = 0.13f),
                        topLeft = Offset(zoneLeft, top),
                        size = Size(zoneWidth, bottom - top)
                    )
                }
            }
            val targetColor = if (isBuy) TradingPositive else TradingNegative
            val stopColor = if (isBuy) TradingNegative else TradingPositive
            drawRiskZone(pos.takeProfit, targetColor)
            drawRiskZone(pos.stopLoss, stopColor)

            // Entry line
            if (isPriceVisible(transform, pos.entryPrice)) {
            scope.drawLine(
                color = lineColor,
                start = Offset(0f, entryY),
                end = Offset(transform.chartWidth, entryY),
                strokeWidth = 1.2f,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 4f), 0f)
            )

            // Badge
            scope.drawContext.canvas.nativeCanvas.apply {
                val p = android.graphics.Paint().apply {
                    color = if (isBuy) android.graphics.Color.parseColor("#10B981") else android.graphics.Color.parseColor("#EF4444")
                    textSize = 19f
                    isAntiAlias = true
                }
                val label = String.format(
                    Locale.US,
                    "%s %.2f lot (%s$%.2f)",
                    if (isBuy) "BUY" else "SELL",
                    pos.volume,
                    if (pos.profitLoss >= 0) "+" else "",
                    pos.profitLoss
                )
                drawText(label, 12f, entryY - 6f, p)
            }

            }
            // Stop Loss line
            pos.stopLoss?.takeIf { isPriceVisible(transform, it) }?.let { sl ->
                val slY = transform.priceToY(sl)
                scope.drawLine(
                    color = TradingNegative.copy(alpha = 0.85f),
                    start = Offset(0f, slY),
                    end = Offset(transform.chartWidth, slY),
                    strokeWidth = 1.2f,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
                )
                scope.drawContext.canvas.nativeCanvas.apply {
                    val p = android.graphics.Paint().apply { color = android.graphics.Color.parseColor("#EF4444"); textSize = 18f; isAntiAlias = true }
                    drawText("SL: " + QuotePriceFormatter.price(sl), 12f, slY - 4f, p)
                }
            }

            // Take Profit line
            pos.takeProfit?.takeIf { isPriceVisible(transform, it) }?.let { tp ->
                val tpY = transform.priceToY(tp)
                scope.drawLine(
                    color = TradingPositive.copy(alpha = 0.85f),
                    start = Offset(0f, tpY),
                    end = Offset(transform.chartWidth, tpY),
                    strokeWidth = 1.2f,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f), 0f)
                )
                scope.drawContext.canvas.nativeCanvas.apply {
                    val p = android.graphics.Paint().apply { color = android.graphics.Color.parseColor("#10B981"); textSize = 18f; isAntiAlias = true }
                    drawText("TP: " + QuotePriceFormatter.price(tp), 12f, tpY - 4f, p)
                }
            }
        }
    }

    fun drawPendingOrders(
        scope: DrawScope,
        transform: ChartTransform,
        orders: List<Order>
    ) {
        for (ord in orders) {
            if (ord.status != OrderStatus.PENDING ||
                !isPriceVisible(transform, ord.requestedPrice)) continue
            val orderY = transform.priceToY(ord.requestedPrice)
            val isBuy = ord.direction == OrderSide.BUY

            scope.drawLine(
                color = TradingGold.copy(alpha = 0.85f),
                start = Offset(0f, orderY),
                end = Offset(transform.chartWidth, orderY),
                strokeWidth = 1.2f,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f), 0f)
            )

            scope.drawContext.canvas.nativeCanvas.apply {
                val p = android.graphics.Paint().apply { color = android.graphics.Color.parseColor("#F59E0B"); textSize = 18f; isAntiAlias = true }
                val label = "${ord.type.name} ${ord.volume} lot"
                drawText(label, 12f, orderY - 5f, p)
            }
        }
    }

    fun drawHistoricalTradeMarkers(
        scope: DrawScope,
        transform: ChartTransform,
        trades: List<TradeJournalEntry>
    ) {
        val firstVisibleTime = transform.visibleCandles.firstOrNull()?.openTime ?: return
        val lastVisibleTime = transform.visibleCandles.lastOrNull()?.openTime ?: return
        for (trade in trades) {
            // ChartTransform.timeToX clamps out-of-viewport timestamps to an edge.
            // Do not draw phantom entries/exits at the viewport boundary.
            val openX = if (trade.openTime in firstVisibleTime..lastVisibleTime)
                transform.timeToX(trade.openTime) else null
            val closeX = if (trade.closeTime in firstVisibleTime..lastVisibleTime)
                transform.timeToX(trade.closeTime) else null
            if (openX == null && closeX == null) continue

            // Open Marker (Triangle)
            if (openX != null && isPriceVisible(transform, trade.entryPrice)) {
                val openY = transform.priceToY(trade.entryPrice)
                val isBuy = trade.side == PositionSide.BUY
                val markerColor = if (isBuy) TradingPositive else TradingNegative

                val triangle = Path().apply {
                    if (isBuy) {
                        moveTo(openX, openY + 4f)
                        lineTo(openX - 6f, openY + 16f)
                        lineTo(openX + 6f, openY + 16f)
                    } else {
                        moveTo(openX, openY - 4f)
                        lineTo(openX - 6f, openY - 16f)
                        lineTo(openX + 6f, openY - 16f)
                    }
                    close()
                }
                scope.drawPath(triangle, markerColor)
            }

            // Close Marker & P/L Tag
            if (closeX != null && isPriceVisible(transform, trade.exitPrice)) {
                val closeY = transform.priceToY(trade.exitPrice)
                val isWin = trade.netProfitLoss >= 0

                scope.drawCircle(
                    color = if (isWin) TradingPositive else TradingNegative,
                    radius = 5f,
                    center = Offset(closeX, closeY)
                )

                scope.drawContext.canvas.nativeCanvas.apply {
                    val p = android.graphics.Paint().apply {
                        color = if (isWin) android.graphics.Color.parseColor("#10B981") else android.graphics.Color.parseColor("#EF4444")
                        textSize = 17f
                        isAntiAlias = true
                    }
                    val plText = String.format(Locale.US, "%s$%.1f", if (isWin) "+" else "", trade.netProfitLoss)
                    drawText(plText, closeX - 18f, closeY - 8f, p)
                }
            }
        }
    }
}
