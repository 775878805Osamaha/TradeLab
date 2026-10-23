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
        // Invalid account data is never a user-configurable risk preference.
        // Disabling trading limits must not permit trades on corrupt balances.
        if (!exposure.initialBalance.isFinite() || exposure.initialBalance <= 0.0 ||
            !exposure.balance.isFinite() || !exposure.equity.isFinite() ||
            exposure.openPositions < 0 || exposure.pendingOrders < 0 ||
            exposure.consecutiveLosses < 0) {
            return "تعذر التحقق من رصيد Replay أو ملكيته"
        }
        if (!limits.enabled) return null
        if (!limits.maxDrawdownPercent.isFinite() || limits.maxDrawdownPercent <= 0.0 ||
            !limits.maxSessionLossUsd.isFinite() || limits.maxSessionLossUsd < 0.0 ||
            limits.maxPositions < 1 || limits.maxOrders < 1 || limits.maxConsecutiveLosses < 0) {
            return "إعدادات حدود المخاطر في Replay غير صالحة"
        }
        // Avoid overflow from multiplying large monetary balances before
        // dividing. Ratio-based drawdown stays finite for finite positive
        // initial balances and is consistent with equity-based loss limits.
        val drawdown = if (exposure.equity >= exposure.initialBalance) 0.0
            else (1.0 - exposure.equity / exposure.initialBalance) * 100.0
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
