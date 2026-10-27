package com.example.feature.chart.model

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.example.data.local.entity.DrawingEntity
import com.example.ui.theme.TradingGold
import java.util.Base64
import java.util.Locale
import kotlin.math.abs

enum class DrawingTool(val displayNameAr: String) {
    NONE("إلغاء التحديد"),
    HORIZONTAL_LINE("خط أفقي (Horizontal Line)"),
    VERTICAL_LINE("خط رأسي (Vertical Line)"),
    TRENDLINE("خط اتجاه (Trendline)"),
    RECTANGLE("مستطيل منطقة (Rectangle)"),
    FIBONACCI("تصحيح فيبوناتشي (Fibonacci)"),
    MEASUREMENT("أداة القياس والمدى (Ruler)"),
    ELLIPSE("بيضاوي"),
    ANNOTATION("تعليق"),
    HORIZONTAL_RAY("شعاع أفقي"), EXTENDED_LINE("خط ممتد"), RAY("شعاع"), INFO_LINE("خط المعلومات"),
    ARROW("سهم"), ARROW_UP("علامة السهم أعلى"), ARROW_DOWN("علامة السهم أسفل"),
    BRUSH("فرشاة"), HIGHLIGHTER("لون مميز"), PATH("مسار"), POLYLINE("متعدد الخطوط"),
    TRIANGLE("مثلث"), ROTATED_RECTANGLE("مستطيل مائل"), CURVE("منحنى"), ARC("قوس"),
    PRICE_RANGE("المدى السعري"), DATE_RANGE("المدى الزمني"), DATE_PRICE_RANGE("نطاق التاريخ والسعر"),
    LONG_POSITION("صفقة شراء"), SHORT_POSITION("صفقة بيع على المكشوف"),
    TEXT("نص"), ANCHORED_TEXT("نص مثبت"), NOTE("ملاحظة"), PRICE_LABEL("بطاقة السعر"),
    CALLOUT("نص تفسيري"), FLAG("علامة تمييز"), PIN("شبك"),
    ABCD("نموذج ABCD"), XABCD("نموذج XABCD"), HEAD_SHOULDERS("نموذج الرأس والكتفين"),
    ELLIOTT_IMPULSE("موجة إليوت الدافعة"), ELLIOTT_CORRECTION("موجة إليوت التصحيحية"),
    ARROW_MARKER("علامة السهم"), CIRCLE("دائرة"), DOUBLE_CURVE("منحنى مزدوج"),
    TABLE("جدول"), PRICE_NOTE("ملصق السعر"), SIGNPOST("لافتة"), IMAGE("صورة"),
    FORECAST("التوقعات"), BARS_PATTERN("نمط الأعمدة"), GHOST_FEED("مسار تخيلي"), PROJECTION("إسقاط"),
    VOLUME_PROFILE_FIXED("بروفايل حجم التداول الثابت"), VOLUME_PROFILE_SESSION("بروفايل أحجام الجلسة"),
    CYPHER("نمط سيفر"), TRIANGLE_PATTERN("نموذج المثلث"), THREE_DRIVES("نموذج الثلاث موجات"),
    ELLIOTT_TRIANGLE("موجة إليوت المثلثية"), ELLIOTT_DOUBLE("موجة إليوت الثنائية"), ELLIOTT_TRIPLE("موجة إليوت المركبة"), CYCLES("خطوط دورية"),
    FIB_FAN("مروحة فيبوناتشي"), PARALLEL_CHANNEL("قناة متوازية"), ANCHORED_VWAP("VWAP مثبت")
}

data class DrawingAnchor(val time: Long, val price: Double)

val DrawingTool.isTextTool: Boolean get() = this in setOf(DrawingTool.TABLE, DrawingTool.PRICE_NOTE, DrawingTool.SIGNPOST, DrawingTool.ANNOTATION, DrawingTool.TEXT, DrawingTool.ANCHORED_TEXT, DrawingTool.NOTE, DrawingTool.CALLOUT)
val DrawingTool.isSinglePoint: Boolean get() = isTextTool || this in setOf(DrawingTool.IMAGE, DrawingTool.VOLUME_PROFILE_SESSION, DrawingTool.HORIZONTAL_LINE, DrawingTool.VERTICAL_LINE, DrawingTool.HORIZONTAL_RAY, DrawingTool.ARROW_UP, DrawingTool.ARROW_DOWN, DrawingTool.PRICE_LABEL, DrawingTool.FLAG, DrawingTool.PIN, DrawingTool.ANCHORED_VWAP)
val DrawingTool.isVariablePath: Boolean get() = this == DrawingTool.PATH || this == DrawingTool.POLYLINE
val DrawingTool.isFreehand: Boolean get() = this == DrawingTool.BRUSH || this == DrawingTool.HIGHLIGHTER
val DrawingTool.anchorCount: Int get() = when(this) {
    DrawingTool.LONG_POSITION, DrawingTool.SHORT_POSITION, DrawingTool.PROJECTION, DrawingTool.TRIANGLE, DrawingTool.PARALLEL_CHANNEL, DrawingTool.CURVE, DrawingTool.ARC, DrawingTool.ROTATED_RECTANGLE -> 3
    DrawingTool.ABCD, DrawingTool.ELLIOTT_CORRECTION -> 4
    DrawingTool.CYPHER, DrawingTool.TRIANGLE_PATTERN, DrawingTool.DOUBLE_CURVE, DrawingTool.XABCD -> 5
    DrawingTool.ELLIOTT_TRIANGLE, DrawingTool.ELLIOTT_IMPULSE -> 6
    DrawingTool.THREE_DRIVES, DrawingTool.ELLIOTT_DOUBLE, DrawingTool.HEAD_SHOULDERS -> 7
    DrawingTool.ELLIOTT_TRIPLE -> 9
    else -> 2
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
    val strokeWidth: Float = 2.0f,
    val text: String = "تعليق",
    val anchors: List<DrawingAnchor> = emptyList(),
    val screenX: Float? = null,
    val screenY: Float? = null,
    val replayCreatedAt: Long? = null
) {
    fun toEntity(): DrawingEntity {
        val json = buildString {
            append("{")
            append("\"startPrice\":$startPrice,")
            append("\"startTime\":$startTime")
            if (endPrice != null) append(",\"endPrice\":$endPrice")
            if (endTime != null) append(",\"endTime\":$endTime")
            append(",\"textBase64\":\"${Base64.getEncoder().encodeToString(text.toByteArray(Charsets.UTF_8))}\"")
            if (anchors.isNotEmpty()) {
                val encoded = anchors.take(512).joinToString(";") { "${it.time}:${it.price}" }
                append(",\"anchorsBase64\":\"${Base64.getEncoder().encodeToString(encoded.toByteArray(Charsets.UTF_8))}\"")
            }
            if (screenX != null && screenY != null) append(",\"screenX\":$screenX,\"screenY\":$screenY")
            if(replayCreatedAt!=null)append(",\"replayCreatedAt\":$replayCreatedAt")
            append("}")
        }
        val hex = String.format(Locale.US, "#%08X", color.toArgb().toLong() and 0xFFFFFFFFL)
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
                val sPrice = Regex("\"startPrice\":([-+0-9.eE]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toDoubleOrNull() ?: return null
                val sTime = Regex("\"startTime\":([0-9]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toLongOrNull() ?: return null
                val ePrice = Regex("\"endPrice\":([-+0-9.eE]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toDoubleOrNull()
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
                    strokeWidth = entity.strokeWidth,
                    text = Regex("\"textBase64\":\"([^\"]*)\"").find(entity.pointsJson)?.groupValues?.get(1)
                        ?.let { String(Base64.getDecoder().decode(it), Charsets.UTF_8) } ?: "تعليق",
                    anchors = Regex("\"anchorsBase64\":\"([^\"]*)\"").find(entity.pointsJson)?.groupValues?.get(1)
                        ?.let { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
                        ?.split(';')?.take(512)?.mapNotNull { item ->
                            val parts = item.split(':'); val t = parts.getOrNull(0)?.toLongOrNull(); val p = parts.getOrNull(1)?.toDoubleOrNull()
                            if (t != null && p != null && p.isFinite() && p > 0) DrawingAnchor(t, p) else null
                        } ?: emptyList(),
                    replayCreatedAt = Regex("\"replayCreatedAt\":([0-9]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toLongOrNull(),
                    screenX = Regex("\"screenX\":([-+0-9.eE]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toFloatOrNull()?.takeIf { it.isFinite() && it in 0f..1f },
                    screenY = Regex("\"screenY\":([-+0-9.eE]+)").find(entity.pointsJson)?.groupValues?.get(1)?.toFloatOrNull()?.takeIf { it.isFinite() && it in 0f..1f }
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
