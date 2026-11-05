package com.example.feature.chart.model

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import com.example.core.model.Timeframe

private fun Boolean.asFlag(): Int = if (this) 1 else 0

enum class FibExtension { NONE, LEFT, RIGHT, BOTH }
enum class FibLabelPosition { LEFT, CENTER, RIGHT }
enum class FibTimeUnit(val label: String, val upperBound: Int) {
    TICKS("تيكات السعر", 1), SECONDS("ثواني", 59), MINUTES("دقائق", 59),
    HOURS("ساعات", 24), DAYS("الأيام", 366), WEEKS("أسابيع", 52),
    MONTHS("الشهور", 12), RANGES("Ranges", 1)
}

data class FibTimeRule(
    val unit: FibTimeUnit,
    val enabled: Boolean = true,
    val from: Int = 1,
    val to: Int = unit.upperBound
)

data class FibonacciLevel(
    val value: Double,
    val color: Color,
    val enabled: Boolean = true
)

/** Persisted independently for each Fibonacci drawing, not shared with chart appearance. */
data class FibonacciSettings(
    val levels: List<FibonacciLevel> = defaultLevels(),
    val trendLine: Boolean = true,
    val extension: FibExtension = FibExtension.NONE,
    val singleColor: Boolean = false,
    val background: Boolean = false,
    val backgroundOpacity: Float = 0.28f,
    val reverse: Boolean = false,
    val showPrices: Boolean = true,
    val showLevels: Boolean = true,
    val showText: Boolean = true,
    val labelsAsPercents: Boolean = false,
    val labelPosition: FibLabelPosition = FibLabelPosition.LEFT,
    val textSize: Int = 12,
    val logarithmic: Boolean = false,
    val timeRules: List<FibTimeRule> = FibTimeUnit.entries.map { FibTimeRule(it) }
) {
    fun isVisibleAt(timeframeCode: String): Boolean {
        val tf = Timeframe.fromCode(timeframeCode)
        val pair = when {
            tf.minutes < 60 -> FibTimeUnit.MINUTES to tf.minutes
            tf.minutes < 1440 -> FibTimeUnit.HOURS to (tf.minutes / 60)
            tf.minutes < 10080 -> FibTimeUnit.DAYS to (tf.minutes / 1440)
            else -> FibTimeUnit.WEEKS to (tf.minutes / 10080)
        }
        return timeRules.firstOrNull { it.unit == pair.first }
            ?.let { it.enabled && pair.second in it.from..it.to } ?: true
    }

    /** Delimited versioned payload. The caller wraps this in Base64 inside DrawingEntity JSON. */
    fun encode(): String = listOf(
        "1",
        levels.take(64).joinToString(";") { "${it.value},${it.enabled.asFlag()},${it.color.toArgb()}" },
        trendLine.asFlag().toString(), extension.name, singleColor.asFlag().toString(),
        background.asFlag().toString(), backgroundOpacity.toString(), reverse.asFlag().toString(),
        showPrices.asFlag().toString(), showLevels.asFlag().toString(), showText.asFlag().toString(),
        labelsAsPercents.asFlag().toString(), labelPosition.name, textSize.toString(),
        logarithmic.asFlag().toString(),
        timeRules.joinToString(";") { "${it.unit.name},${it.enabled.asFlag()},${it.from},${it.to}" }
    ).joinToString("|")

    companion object {
        /** Existing drawings have no Fibonacci settings payload; preserve their former full-width levels. */
        fun legacy(): FibonacciSettings = FibonacciSettings(
            levels = FibonacciCalculator.DEFAULT_LEVELS.map { FibonacciLevel(it, Color.White) },
            trendLine = false, extension = FibExtension.BOTH, singleColor = true,
            labelsAsPercents = true
        )

        fun defaultLevels(): List<FibonacciLevel> = listOf(
            FibonacciLevel(0.0, Color(0xFFF6384D)),
            FibonacciLevel(0.382, Color(0xFFF4F4F4), false),
            FibonacciLevel(0.618, Color(0xFFFFF39A), false),
            FibonacciLevel(-2.5, Color.White),
            FibonacciLevel(-4.0, Color(0xFFFFEA39)),
            FibonacciLevel(0.5, Color(0xFFFFEF8B), false),
            FibonacciLevel(0.786, Color.White, false),
            FibonacciLevel(0.667, Color(0xFFFFF39A), false),
            FibonacciLevel(1.0, Color(0xFF1A9D8C)),
            FibonacciLevel(1.5, Color(0xFF4CAF50)),
            FibonacciLevel(1.8, Color(0xFF4CAF50)),
            FibonacciLevel(-1.5, Color(0xFF4CAF50)),
            FibonacciLevel(-1.8, Color(0xFF4CAF50)),
            FibonacciLevel(-2.0, Color(0xFF4CAF50)),
            FibonacciLevel(-3.5, Color(0xFF009688)),
            FibonacciLevel(3.414, Color(0xFF8CA8F8), false),
            FibonacciLevel(4.0, Color(0xFFF392A1), false),
            FibonacciLevel(4.272, Color(0xFFC38DCE), false),
            FibonacciLevel(4.414, Color(0xFFEB7EA3), false),
            FibonacciLevel(4.618, Color(0xFFF9C478), false),
            FibonacciLevel(4.764, Color(0xFF76C6BB), false)
        )

        fun decode(value: String?): FibonacciSettings {
            if (value.isNullOrBlank()) return FibonacciSettings()
            return runCatching {
                val p = value.split('|')
                require(p.size == 16 && p[0] == "1")
                fun bit(raw: String): Boolean { require(raw == "0" || raw == "1"); return raw == "1" }
                val levels = p[1].split(';').map { item ->
                    val fields = item.split(','); require(fields.size == 3)
                    val number = fields[0].toDouble()
                    require(number.isFinite() && number in -100.0..100.0)
                    FibonacciLevel(number, Color(fields[2].toInt()), bit(fields[1]))
                }
                require(levels.isNotEmpty() && levels.size <= 64)
                val rules = p[15].split(';').map { item ->
                    val f = item.split(','); require(f.size == 4)
                    val unit = FibTimeUnit.valueOf(f[0])
                    val from = f[2].toInt(); val to = f[3].toInt()
                    require(from in 1..unit.upperBound && to in from..unit.upperBound)
                    FibTimeRule(unit, bit(f[1]), from, to)
                }
                require(rules.map { it.unit }.distinct().size == FibTimeUnit.entries.size)
                val opacity = p[6].toFloat()
                val fontSize = p[13].toInt()
                require(opacity.isFinite() && opacity in 0f..1f && fontSize in 8..32)
                FibonacciSettings(levels, bit(p[2]), FibExtension.valueOf(p[3]), bit(p[4]),
                    bit(p[5]), opacity, bit(p[7]), bit(p[8]), bit(p[9]), bit(p[10]),
                    bit(p[11]), FibLabelPosition.valueOf(p[12]), fontSize, bit(p[14]), rules)
            }.getOrDefault(FibonacciSettings())
        }
    }
}
