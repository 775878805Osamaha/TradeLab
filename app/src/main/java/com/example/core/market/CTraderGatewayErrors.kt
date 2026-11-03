package com.example.core.market

import java.io.IOException

/** Only the gateway's public, allowlisted error categories may appear in the UI. */
object CTraderGatewayErrors {
    private val messages = mapOf(
        "ctrader_connection_failed" to "فشل اتصال بوابة Vercel بخادم cTrader",
        "ctrader_response_timeout" to "انتهت مهلة استجابة خادم cTrader",
        "ctrader_broker_rejected_request" to "رفض خادم cTrader طلب القراءة؛ يلزم فحص سبب الرفض في سجلات البوابة",
        "ctrader_broker_unavailable" to "فشل الطلب داخل بوابة cTrader؛ يلزم فحص سجلات Vercel",
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

class CTraderGatewayException(val statusCode: Int, val errorCode: String?) :
    IOException(CTraderGatewayErrors.explain(statusCode, errorCode))
