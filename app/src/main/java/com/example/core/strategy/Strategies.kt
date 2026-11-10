package com.example.core.strategy

import java.util.concurrent.ConcurrentHashMap

/**
 * StrategyRegistry manages active trading strategies and user presets.
 * Provides one explicitly educational starter strategy and dynamic registration
 * for user-defined strategies. No profitability assumptions are embedded.
 */
object StrategyRegistry {
    private val strategies = ConcurrentHashMap<String, Strategy>()
    private val presets = ConcurrentHashMap<String, MutableList<StrategyPreset>>()

    init {
        resetToDefaults()
    }

    fun resetToDefaults() {
        strategies.clear()
        presets.clear()
        register(SmaCrossoverExample())
    }

    val AVAILABLE_STRATEGIES: List<Strategy>
        get() = getAllStrategies()

    fun getAllStrategies(): List<Strategy> = strategies.values.sortedBy { it.id }

    fun getStrategy(id: String): Strategy? {
        return strategies.values.firstOrNull { it.id.equals(id, ignoreCase = true) }
    }

    fun register(strategy: Strategy) {
        strategies[strategy.id.uppercase()] = strategy
    }

    fun unregister(id: String) {
        strategies.remove(id.uppercase())
        presets.remove(id.uppercase())
    }

    fun getPresetsForStrategy(strategyId: String): List<StrategyPreset> {
        return presets[strategyId.uppercase()] ?: emptyList()
    }

    fun savePreset(preset: StrategyPreset) {
        val list = presets.getOrPut(preset.strategyId.uppercase()) { mutableListOf() }
        list.removeAll { it.id.equals(preset.id, ignoreCase = true) }
        list.add(preset)
    }

    fun deletePreset(presetId: String) {
        for (list in presets.values) {
            list.removeAll { it.id.equals(presetId, ignoreCase = true) }
        }
    }
}
