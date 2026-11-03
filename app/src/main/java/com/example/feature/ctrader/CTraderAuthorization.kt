package com.example.feature.ctrader

import android.net.Uri

/**
 * Browser-only, read-only cTrader authorization. No client secret is embedded in the APK.
 * Authorization codes must be exchanged by a trusted backend before market access.
 */
object CTraderAuthorization {
    const val CLIENT_ID = "46509"
    const val REDIRECT_URI = "tradelab://oauth/ctrader"

    fun authorizationUrl():Uri = Uri.parse(
        "https://id.ctrader.com/my/settings/openapi/grantingaccess/"
    ).buildUpon()
        .appendQueryParameter("client_id", CLIENT_ID)
        .appendQueryParameter("redirect_uri", REDIRECT_URI)
        .appendQueryParameter("scope", "accounts")
        .appendQueryParameter("product", "web")
        .build()

    fun isCallback(uri:Uri?):Boolean =
        uri?.scheme == "tradelab" && uri.host == "oauth" &&
            uri.path == "/ctrader"

    fun callbackStatus(uri:Uri?):String? {
        if(!isCallback(uri)) return null
        if(!uri?.getQueryParameter("error").isNullOrBlank())
            return "رفض المستخدم ربط حساب cTrader أو فشلت المصادقة."
        return if(!uri?.getQueryParameter("code").isNullOrBlank())
            "وصل رمز التفويض من cTrader. يتطلب إكمال الربط خدمة آمنة لتبادل الرمز؛ لم يتم تفعيل الأسعار بعد."
        else "لم يصل رمز تفويض صالح من cTrader."
    }
}
