package com.example.feature.replay

/**
 * Deterministic pre-trade circuit breaker shared by market orders, strategies
 * and pending-order fills. Never closes existing positions or modifies history.
 */
object ReplayRiskPolicy {
    data class Limits(
        val enabled: Boolean = true,
        val maxPositions: Int = 10,
        val maxOrders: Int = 20,
        val maxDrawdownPercent: Double = 100.0,
        val maxConsecutiveLosses: Int = 0,
        val maxSessionLossUsd: Double = 0.0
    )

    data class Exposure(
        val initialBalance: Double,
        val balance: Double,
        val equity: Double,
        val openPositions: Int,
        val pendingOrders: Int,
        val consecutiveLosses: Int
    )

    fun consecutiveLosses(closedTradePnls: List<Double>): Int {
        var count = 0
        for (pnl in closedTradePnls.asReversed()) {
            if (!pnl.isFinite() || pnl >= 0.0) break
            count++
        }
        return count
    }

    fun blockReason(limits: Limits, exposure: Exposure, isPending: Boolean): String? {
        if (!limits.enabled) return null
        if (!exposure.initialBalance.isFinite() || exposure.initialBalance <= 0.0 ||
            !exposure.balance.isFinite() || !exposure.equity.isFinite()) {
            return "تعذر التحقق من رصيد Replay أو ملكيته"
        }
        val drawdown = (exposure.initialBalance - exposure.equity).coerceAtLeast(0.0) *
            100.0 / exposure.initialBalance
        val realizedLoss = (exposure.initialBalance - exposure.balance).coerceAtLeast(0.0)
        return when {
            limits.maxConsecutiveLosses > 0 && exposure.consecutiveLosses >= limits.maxConsecutiveLosses ->
                "تم بلوغ حد الخسائر المتتالية لجلسة Replay"
            limits.maxSessionLossUsd > 0.0 && realizedLoss >= limits.maxSessionLossUsd ->
                "تم بلوغ الحد الأقصى للخسارة المحققة لجلسة Replay"
            drawdown >= limits.maxDrawdownPercent -> "تم بلوغ حد التراجع المسموح في جلسة Replay"
            isPending && exposure.pendingOrders >= limits.maxOrders ->
                "تم بلوغ الحد الأقصى للأوامر المعلقة"
            !isPending && exposure.openPositions >= limits.maxPositions ->
                "تم بلوغ الحد الأقصى للصفقات المفتوحة"
            else -> null
        }
    }
}
