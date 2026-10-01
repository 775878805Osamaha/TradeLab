package com.example.core.execution

import com.example.core.market.DefaultSymbols
import com.example.core.model.*

enum class OrderRejectionReason(val code: String, val messageAr: String, val messageEn: String) {
    INVALID_SYMBOL("INVALID_SYMBOL", "الرمز المالي غير موجود أو غير مدعوم", "Invalid symbol"),
    INVALID_VOLUME("INVALID_VOLUME", "حجم العقد غير صحيح (أقل من الحد الأدنى أو يتجاوز الحد الأقصى أو غير متوافق مع خطوة اللوت)", "Invalid volume size"),
    INSUFFICIENT_MARGIN("INSUFFICIENT_MARGIN", "الهامش المتاح في الحساب غير كافٍ لتنفيذ هذا الأمر", "Insufficient free margin"),
    INVALID_SL("INVALID_SL", "مستوى وقف الخسارة غير صالح للاتجاه المطلوب", "Invalid Stop Loss placement"),
    INVALID_TP("INVALID_TP", "مستوى جني الأرباح غير صالح للاتجاه المطلوب", "Invalid Take Profit placement"),
    INVALID_PRICE("INVALID_PRICE", "سعر تنفيذ الأمر المعلق غير منطقي مع السعر السوقي الحالي", "Invalid price for pending order")
}

sealed class OrderValidationResult {
    object Valid : OrderValidationResult()
    data class Rejected(val reason: OrderRejectionReason, val details: String? = null) : OrderValidationResult() {
        val message: String get() = details ?: reason.messageAr
    }

    val isValid: Boolean get() = this is Valid
}

object OrderValidator {

    /**
     * Validates a market or pending order against account balance, symbol specifications, and market prices.
     */
    fun validate(
        account: VirtualAccount,
        symbol: String,
        type: OrderType,
        side: OrderSide,
        volume: Double,
        tick: Tick?,
        requestedPrice: Double? = null,
        stopLoss: Double? = null,
        takeProfit: Double? = null
    ): OrderValidationResult {
        // 1. Symbol validation
        val symInfo = DefaultSymbols.SYMBOLS.firstOrNull {
            it.symbol.equals(symbol, ignoreCase = true) ||
            (symbol.equals("BTCUSD", ignoreCase = true) && it.symbol == "BTCUSDT") ||
            (symbol.equals("ETHUSD", ignoreCase = true) && it.symbol == "ETHUSDT")
        } ?: return OrderValidationResult.Rejected(OrderRejectionReason.INVALID_SYMBOL)

        // 2. Volume validation
        if (volume < symInfo.minLot) {
            return OrderValidationResult.Rejected(
                OrderRejectionReason.INVALID_VOLUME,
                "حجم اللوت ($volume) أقل من الحد الأدنى (${symInfo.minLot})"
            )
        }
        if (volume > symInfo.maxLot) {
            return OrderValidationResult.Rejected(
                OrderRejectionReason.INVALID_VOLUME,
                "حجم اللوت ($volume) أكبر من الحد الأقصى (${symInfo.maxLot})"
            )
        }

        // Validate volume step precision
        val steps = (volume - symInfo.minLot) / symInfo.lotStep
        val roundedSteps = kotlin.math.round(steps)
        if (kotlin.math.abs(steps - roundedSteps) > 0.0001) {
            return OrderValidationResult.Rejected(
                OrderRejectionReason.INVALID_VOLUME,
                "حجم اللوت ($volume) غير متوافق مع خطوة العقد (${symInfo.lotStep})"
            )
        }

        // 3. Price resolution
        val referencePrice = when (type) {
            OrderType.MARKET -> {
                if (tick == null) {
                    return OrderValidationResult.Rejected(
                        OrderRejectionReason.INVALID_PRICE,
                        "بيانات السوق غير متوفرة لتحديد السعر الحالي"
                    )
                }
                if (side == OrderSide.BUY) tick.ask else tick.bid
            }
            OrderType.BUY_LIMIT, OrderType.BUY_STOP, OrderType.SELL_LIMIT, OrderType.SELL_STOP, OrderType.LIMIT, OrderType.STOP -> {
                requestedPrice ?: return OrderValidationResult.Rejected(
                    OrderRejectionReason.INVALID_PRICE,
                    "يجب تحديد السعر المستهدف للأمر المعلق"
                )
            }
        }

        // 4. Pending Order Price logic
        if (tick != null) {
            when (type) {
                OrderType.BUY_LIMIT -> {
                    if (referencePrice >= tick.ask) {
                        return OrderValidationResult.Rejected(
                            OrderRejectionReason.INVALID_PRICE,
                            "أمر Buy Limit يتطلب سعراً أقل من سعر الطلب الحالي (${tick.ask})"
                        )
                    }
                }
                OrderType.SELL_LIMIT -> {
                    if (referencePrice <= tick.bid) {
                        return OrderValidationResult.Rejected(
                            OrderRejectionReason.INVALID_PRICE,
                            "أمر Sell Limit يتطلب سعراً أعلى من سعر العرض الحالي (${tick.bid})"
                        )
                    }
                }
                OrderType.BUY_STOP -> {
                    if (referencePrice <= tick.ask) {
                        return OrderValidationResult.Rejected(
                            OrderRejectionReason.INVALID_PRICE,
                            "أمر Buy Stop يتطلب سعراً أعلى من سعر الطلب الحالي (${tick.ask})"
                        )
                    }
                }
                OrderType.SELL_STOP -> {
                    if (referencePrice >= tick.bid) {
                        return OrderValidationResult.Rejected(
                            OrderRejectionReason.INVALID_PRICE,
                            "أمر Sell Stop يتطلب سعراً أقل من سعر العرض الحالي (${tick.bid})"
                        )
                    }
                }
                else -> {}
            }
        }

        // 5. Margin validation
        val requiredMargin = (volume * symInfo.contractSize * referencePrice) / account.leverage
        if (requiredMargin > account.freeMargin) {
            return OrderValidationResult.Rejected(
                OrderRejectionReason.INSUFFICIENT_MARGIN,
                "الهامش المطلوب (${String.format("%.2f", requiredMargin)}$) يتجاوز الهامش الحر المتاح (${String.format("%.2f", account.freeMargin)}$)"
            )
        }

        // 6. Stop Loss validation
        if (stopLoss != null) {
            if (side == OrderSide.BUY && stopLoss >= referencePrice) {
                return OrderValidationResult.Rejected(
                    OrderRejectionReason.INVALID_SL,
                    "وقف الخسارة لشراء يجب أن يكون أدنى من سعر الدخول ($referencePrice)"
                )
            }
            if (side == OrderSide.SELL && stopLoss <= referencePrice) {
                return OrderValidationResult.Rejected(
                    OrderRejectionReason.INVALID_SL,
                    "وقف الخسارة لبيع يجب أن يكون أعلى من سعر الدخول ($referencePrice)"
                )
            }
        }

        // 7. Take Profit validation
        if (takeProfit != null) {
            if (side == OrderSide.BUY && takeProfit <= referencePrice) {
                return OrderValidationResult.Rejected(
                    OrderRejectionReason.INVALID_TP,
                    "جني الأرباح لشراء يجب أن يكون أعلى من سعر الدخول ($referencePrice)"
                )
            }
            if (side == OrderSide.SELL && takeProfit >= referencePrice) {
                return OrderValidationResult.Rejected(
                    OrderRejectionReason.INVALID_TP,
                    "جني الأرباح لبيع يجب أن يكون أدنى من سعر الدخول ($referencePrice)"
                )
            }
        }

        return OrderValidationResult.Valid
    }
}
