package com.example.ui.components.chart

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

    // ChartTransform clamps offscreen prices to the plot boundary. Skip those
    // levels rather than drawing misleading horizontal lines at the top/bottom.
    private fun isPriceVisible(transform: ChartTransform, price: Double): Boolean =
        price.isFinite() && price in transform.minPrice..transform.maxPrice

    fun drawPriceAndSpread(
        scope: DrawScope,
        transform: ChartTransform,
        latestTick: Tick?
    ) {
        if (latestTick == null) return
        if (!isPriceVisible(transform, latestTick.last) &&
            !isPriceVisible(transform, latestTick.bid) &&
            !isPriceVisible(transform, latestTick.ask)) return

        val bidY = transform.priceToY(latestTick.bid)
        val askY = transform.priceToY(latestTick.ask)
        val lastY = transform.priceToY(latestTick.last)

        // 1. Bid line (Dashed green)
        scope.drawLine(
            color = TradingPositive.copy(alpha = 0.7f),
            start = Offset(0f, bidY),
            end = Offset(transform.chartWidth, bidY),
            strokeWidth = 1f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f)
        )

        // 2. Ask line (Dashed red)
        scope.drawLine(
            color = TradingNegative.copy(alpha = 0.7f),
            start = Offset(0f, askY),
            end = Offset(transform.chartWidth, askY),
            strokeWidth = 1f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f)
        )

        // 3. Current Price line (Solid accent)
        scope.drawLine(
            color = TradingAccent,
            start = Offset(0f, lastY),
            end = Offset(transform.chartWidth, lastY),
            strokeWidth = 1.5f
        )

        // Price badge on the right axis
        scope.drawContext.canvas.nativeCanvas.apply {
            val bgPaint = android.graphics.Paint().apply {
                color = android.graphics.Color.parseColor("#3B82F6")
            }
            val textPaint = android.graphics.Paint().apply {
                color = android.graphics.Color.WHITE
                textSize = 22f
                isAntiAlias = true
            }
            val text = String.format(Locale.US, "%.2f", latestTick.last)
            drawRect(transform.chartWidth, lastY - 14f, transform.chartWidth + 80f, lastY + 14f, bgPaint)
            drawText(text, transform.chartWidth + 6f, lastY + 8f, textPaint)

            // Spread badge
            val spreadPips = latestTick.spread * 10.0 // pip estimation
            val spreadText = String.format(Locale.US, "سبريد: %.1f", spreadPips)
            val spreadPaint = android.graphics.Paint().apply {
                color = android.graphics.Color.parseColor("#9CA3AF")
                textSize = 18f
                isAntiAlias = true
            }
            drawText(spreadText, transform.chartWidth - 95f, 24f, spreadPaint)
        }
    }

    fun drawOpenPositions(
        scope: DrawScope,
        transform: ChartTransform,
        positions: List<Position>
    ) {
        for (pos in positions) {
            if (!isPriceVisible(transform, pos.entryPrice)) continue
            val entryY = transform.priceToY(pos.entryPrice)
            val isBuy = pos.side == PositionSide.BUY
            val lineColor = if (isBuy) TradingPositive else TradingNegative

            // Entry line
            scope.drawLine(
                color = lineColor,
                start = Offset(0f, entryY),
                end = Offset(transform.chartWidth, entryY),
                strokeWidth = 1.5f,
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
                    drawText("SL: " + String.format(Locale.US, "%.2f", sl), 12f, slY - 4f, p)
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
                    drawText("TP: " + String.format(Locale.US, "%.2f", tp), 12f, tpY - 4f, p)
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
