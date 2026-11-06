package com.example.core.market

/** Explicit publication boundary for a verified historical source; never infer gaps from the clock. */
class ChartHistoryPublicationGapException(val publishedUntil: Long) : MarketDataRequestException(
    "الفترة المطلوبة تتجاوز آخر شمعة تاريخية منشورة من مصدر السوق"
)
