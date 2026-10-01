package com.example.core.strategy

object StrategyFactory {
    fun createStrategy(strategyId: String): Strategy? {
        val strat = StrategyRegistry.getStrategy(strategyId)
        strat?.reset()
        return strat
    }

    fun getAllAvailable(): List<Strategy> {
        return StrategyRegistry.getAllStrategies()
    }
}
