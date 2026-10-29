package com.example.core.market

/** Exclusive source boundary, derived from validated published records, never from the clock. */
class ChartHistoryPublicationGapException(val publishedUntil: Long) : MarketDataRequestException(
    "تأخر نشر أرشيف HistData: الفترة المطلوبة تتجاوز آخر دقيقة منشورة"
)
