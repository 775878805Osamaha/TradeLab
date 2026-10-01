package com.example.feature.chart.model

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.example.data.local.entity.DrawingEntity
import com.example.ui.theme.TradingGold
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs

enum class DrawingTool(val displayNameAr: String) {
    NONE("إلغاء التحديد"),
    HORIZONTAL_LINE("خط أفقي (Horizontal Line)"),
    VERTICAL_LINE("خط رأسي (Vertical Line)"),
    TRENDLINE("خط اتجاه (Trendline)"),
    RECTANGLE("مستطيل منطقة (Rectangle)"),
    FIBONACCI("تصحيح فيبوناتشي (Fibonacci)"),
    MEASUREMENT("أداة القياس والمدى (Ruler)")
}

data class ChartDrawing(
    val id: Long = 0,
    val tool: DrawingTool,
    val symbol: String,
    val timeframe: String,
    val startPrice: Double,
    val startTime: Long,
    val endPrice: Double? = null,
    val endTime: Long? = null,
    val color: Color = TradingGold,
    val strokeWidth: Float = 2.0f
) {
    fun toEntity(): DrawingEntity {
        val json = buildString {
            append("{")
            append("\"startPrice\":$startPrice,")
            append("\"startTime\":$startTime")
            if (endPrice != null) append(",\"endPrice\":$endPrice")
            if (endTime != null) append(",\"endTime\":$endTime")
            append("}")
        }
        val hex = String.format(Locale.US, "#%08X", color.value.toLong())
        return DrawingEntity(
            id = id,
            symbol = symbol,
            timeframe = timeframe,
            type = tool.name,
            pointsJson = json,
            colorHex = hex,
            strokeWidth = strokeWidth
        )
    }

    companion object {
        fun fromEntity(entity: DrawingEntity): ChartDrawing? {
            val tool = try {
                DrawingTool.valueOf(entity.type)
            } catch (e: Exception) {
                return null
            }
            return try {
                val sPrice = Regex("\"startPrice\":([0-9.-]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toDoubleOrNull() ?: return null
                val sTime = Regex("\"startTime\":([0-9]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toLongOrNull() ?: return null
                val ePrice = Regex("\"endPrice\":([0-9.-]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toDoubleOrNull()
                val eTime = Regex("\"endTime\":([0-9]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toLongOrNull()

                val parsedColor = entity.colorHex.removePrefix("#").toLongOrNull(16)?.let { Color(it.toInt()) } ?: TradingGold

                ChartDrawing(
                    id = entity.id,
                    tool = tool,
                    symbol = entity.symbol,
                    timeframe = entity.timeframe,
                    startPrice = sPrice,
                    startTime = sTime,
                    endPrice = ePrice,
                    endTime = eTime,
                    color = parsedColor,
                    strokeWidth = entity.strokeWidth
                )
            } catch (e: Exception) {
                null
            }
        }
    }
}

object FibonacciCalculator {
    val DEFAULT_LEVELS = listOf(0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0)

    fun calculateLevels(startPrice: Double, endPrice: Double, levels: List<Double> = DEFAULT_LEVELS): List<Pair<Double, Double>> {
        val diff = endPrice - startPrice
        return levels.map { lvl ->
            Pair(lvl, startPrice + (diff * lvl))
        }
    }
}

object MeasurementCalculator {
    data class MeasurementResult(
        val priceDiff: Double,
        val percentDiff: Double,
        val durationMillis: Long,
        val durationFormatted: String
    )

    fun calculate(
        startPrice: Double,
        endPrice: Double,
        startTime: Long,
        endTime: Long
    ): MeasurementResult {
        val pDiff = endPrice - startPrice
        val pct = if (startPrice != 0.0) (pDiff / startPrice) * 100.0 else 0.0
        val dMillis = abs(endTime - startTime)
        val minutes = dMillis / 60000
        val hours = minutes / 60
        val formatted = if (hours > 0) "${hours}h ${minutes % 60}m" else "${minutes}m"

        return MeasurementResult(
            priceDiff = pDiff,
            percentDiff = pct,
            durationMillis = dMillis,
            durationFormatted = formatted
        )
    }
}
