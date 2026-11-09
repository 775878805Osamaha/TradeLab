package com.example.core.market

import java.io.IOException

/** Only the gateway's public, allowlisted error categories may appear in the UI. */
object CTraderGatewayErrors {
    private val messages = mapOf(
        "ctrader_connection_failed" to "فشل اتصال بوابة Vercel بخادم cTrader",
        "ctrader_response_timeout" to "انتهت مهلة استجابة خادم cTrader",
        "ctrader_broker_rejected_request" to "رفض خادم cTrader طلب القراءة",
        "ctrader_broker_unavailable" to "فشل الطلب داخل بوابة cTrader؛ يلزم فحص سجلات Vercel",
        "ctrader_tick_history_unusable" to "بيانات Tick التاريخية من cTrader ناقصة أو غير قابلة للترقيم دون فجوات",
        "ctrader_token_exchange_failed" to "فشل تجديد أو تبادل رمز تفويض cTrader",
        "ctrader_view_only_required" to "صلاحية التفويض ليست للقراءة فقط؛ أعد التفويض بصلاحية accounts",
        "authentication_paused_for_security" to "بوابة cTrader متوقفة إداريًا",
        "gateway_not_configured" to "بوابة cTrader لا تحتوي إعدادات التشغيل المطلوبة",
        "session_expired" to "انتهت جلسة cTrader؛ أعد ربط الحساب",
        "account_not_authorized" to "الحساب غير مخوّل لهذا التفويض",
        "invalid_request" to "بوابة cTrader رفضت معاملات الطلب"
    )

    fun explain(status: Int, code: String?): String {
        val known = code?.takeIf { it.matches(Regex("[a-z][a-z0-9_]{2,70}")) }
        return if (known != null && messages.containsKey(known)) "${messages.getValue(known)} ($known / HTTP $status)"
        else "فشل طلب بوابة cTrader (HTTP $status)؛ يلزم فحص سجلات Vercel"
    }
}

class CTraderGatewayException(
    val statusCode: Int,
    val errorCode: String?,
    stage: String? = null,
    brokerCode: String? = null,
    operation: Int? = null,
) : IOException(buildString {
    append(CTraderGatewayErrors.explain(statusCode, errorCode))
    if (errorCode == "ctrader_broker_rejected_request") {
        val details = listOfNotNull(
            stage?.takeIf { it in setOf("accounts", "symbols", "candles", "ticks", "spot") },
            operation?.takeIf { it in setOf(2100, 2149, 2102, 2114, 2137, 2145, 2127) }?.toString(),
            brokerCode?.takeIf { it.matches(Regex("[A-Z][A-Z0-9_]{1,63}")) },
        )
        if (details.isNotEmpty()) append(details.joinToString(" / ", prefix = " [", postfix = "]"))
    }
})
