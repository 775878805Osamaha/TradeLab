package com.example.core.model

enum class OrderType(val displayNameAr: String) {
    MARKET("سوقي (Market)"),
    LIMIT("حدي (Limit)"),
    STOP("إيقاف (Stop)"),
    BUY_LIMIT("شراء حدي (Buy Limit)"),
    SELL_LIMIT("بيع حدي (Sell Limit)"),
    BUY_STOP("شراء إيقاف (Buy Stop)"),
    SELL_STOP("بيع إيقاف (Sell Stop)")
}

enum class OrderSide(val displayNameAr: String) {
    BUY("شراء"),
    SELL("بيع")
}

enum class OrderStatus {
    PENDING,
    FILLED,
    PARTIALLY_FILLED,
    CANCELLED,
    REJECTED,
    EXPIRED
}

data class Order(
    val id: Long = 0,
    val accountId: Long,
    val symbol: String,
    val direction: OrderSide,
    val type: OrderType,
    val volume: Double,
    val requestedPrice: Double,
    val executionPrice: Double? = null,
    val stopLoss: Double? = null,
    val takeProfit: Double? = null,
    val status: OrderStatus = OrderStatus.PENDING,
    val createdAt: Long = System.currentTimeMillis(),
    val filledAt: Long? = null,
    val cancelledAt: Long? = null,
    val commission: Double = 0.0,
    val swap: Double = 0.0,
    val slippage: Double = 0.0,
    val comment: String? = null
) : java.io.Serializable {
    // Backwards-compatible aliases
    val side: OrderSide get() = direction
    val executedPrice: Double? get() = executionPrice
    val executedAt: Long? get() = filledAt
}
