package com.example.core.market

import com.example.core.model.DataSourceType
import com.example.core.model.ProviderConnectionStatus

data class MarketDataDiagnostic(
    val providerName: String,
    val connectionStatus: ProviderConnectionStatus,
    val dataSourceType: DataSourceType,
    val lastUpdateTimestamp: Long,
    val reconnectCount: Int,
    val cachedCandlesCount: Long,
    val latestCandleTimestamp: Long,
    val latestTickTimestamp: Long,
    val validationErrorsCount: Int,
    val isStale: Boolean,
    val approximateLatencyMs: Long
)
