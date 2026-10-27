package com.example.feature.results

/** A chronological axis, shared by plotting, axis labels and hit testing.
 * Equal timestamps remain coincident; no artificial elapsed time is inserted.
 */
internal class ResultsChartTimeline(private val times: List<Long>) {
    private val first = times.firstOrNull() ?: 0L
    val duration: Long = ((times.lastOrNull() ?: first) - first).coerceAtLeast(0L)

    fun fraction(time: Long): Double = if (duration == 0L) .5
        else ((time - first).toDouble() / duration).coerceIn(0.0, 1.0)

    fun timeAt(fraction: Double): Long = first + (duration * fraction.coerceIn(0.0, 1.0)).toLong()

    fun nearest(fraction: Double): Int? {
        if (times.isEmpty()) return null
        val target = timeAt(fraction)
        // Upper bound chooses the most recent event when several share a timestamp.
        var low = 0
        var high = times.size
        while (low < high) {
            val mid = (low + high) ushr 1
            if (times[mid] <= target) low = mid + 1 else high = mid
        }
        if (low == 0) return 0
        if (low == times.size) return times.lastIndex
        return if (target - times[low - 1] <= times[low] - target) low - 1 else low
    }
}
