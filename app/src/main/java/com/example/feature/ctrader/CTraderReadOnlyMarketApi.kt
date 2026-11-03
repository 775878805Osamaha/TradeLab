package com.example.feature.ctrader

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** Consumer of the *read-only* gateway REST contract; broker credentials never leave the server. */
class CTraderReadOnlyMarketApi(private val context: Context) {
    data class BrokerAccount(val accountId: String, val broker: String, val isLive: Boolean)
    data class BrokerSymbol(val symbolId: Long, val name: String)
    data class BrokerCandle(
        val timestampMs: Long,
        val open: Double, val high: Double, val low: Double, val close: Double,
        val volume: Long
    )
    data class BrokerQuote(val bid: Double?, val ask: Double?, val timestamp: Long?)

    // A cold cTrader gateway must first open a JSON WebSocket, authenticate
    // the application and then authenticate the user's broker account. Its
    // first historical request can therefore take longer than a warm request.
    // Keep the UI asynchronous; do not mistake the first 18 seconds for a 503.
    private val http=OkHttpClient.Builder()
        .connectTimeout(10,TimeUnit.SECONDS)
        .readTimeout(55,TimeUnit.SECONDS)
        .callTimeout(60,TimeUnit.SECONDS)
        .build()

    private suspend fun fetch(path: String, query: Map<String,String> = emptyMap()): JSONObject =
        withContext(Dispatchers.IO) {
            if(!CTraderAuthorization.isConfigured) throw IllegalStateException("Gateway not configured")
            val token=CTraderAuthorization.sessionForReadOnlyRequests(context)
                ?: throw IllegalStateException("cTrader not linked")
            val uri=Uri.parse(CTraderAuthorization.gatewayBase + path).buildUpon()
            for((name,value) in query) uri.appendQueryParameter(name,value)
            val request=Request.Builder().url(uri.build().toString())
                .header("Authorization","Bearer $token")
                .header("Accept","application/json").build()
            val response=try {
                http.newCall(request).execute()
            } catch(timeout: java.net.SocketTimeoutException) {
                throw java.io.IOException("انتهت مهلة الاتصال مع cTrader بعد انتظار استجابة الوسيط؛ أعد المحاولة.", timeout)
            }
            response.use { response ->
                response.header("X-TradeLab-Session")?.let { CTraderAuthorization.rotateSession(context, it) }
                if(!response.isSuccessful) {
                    val body=response.body?.string().orEmpty()
                    val error=runCatching { JSONObject(body).optString("error") }.getOrDefault("")
                    val message=when(error) {
                        "ctrader_connection_failed" -> "خادم Vercel لا يستطيع الاتصال بخوادم cTrader الآن (503)."
                        "ctrader_response_timeout" -> "انتهت مهلة استجابة cTrader. حاول فحص الاتصال مجددًا."
                        "ctrader_broker_rejected_request" -> "رفض وسيط cTrader طلب قراءة البيانات لهذا الحساب."
                        "ctrader_view_only_required" -> "صلاحية cTrader ليست للقراءة فقط؛ أعد التفويض."
                        "ctrader_token_exchange_failed" -> "تعذر تحديث إذن cTrader. سجّل الدخول مجددًا."
                        "session_expired" -> "انتهت جلسة cTrader. سجّل الدخول مجددًا."
                        "authentication_paused_for_security" -> "خدمة cTrader متوقفة مؤقتًا."
                        else -> "خدمة cTrader غير متاحة الآن (HTTP ${response.code})."
                    }
                    throw java.io.IOException(message)
                }
                JSONObject(response.body?.string().orEmpty())
            }
        }

    suspend fun accounts(): List<BrokerAccount> {
        val array=fetch("/v1/accounts").optJSONArray("accounts") ?: JSONArray()
        return (0 until array.length()).mapNotNull { index ->
            val item=array.optJSONObject(index) ?: return@mapNotNull null
            val id=item.optString("accountId")
            if(!id.matches(Regex("^[0-9]+$")))return@mapNotNull null
            BrokerAccount(id,item.optString("broker"),item.optBoolean("isLive"))
        }
    }

    suspend fun symbols(accountId:String): List<BrokerSymbol> {
        val array=fetch("/v1/symbols",mapOf("accountId" to accountId)).optJSONArray("symbols") ?: JSONArray()
        return (0 until array.length()).mapNotNull { index ->
            val item=array.optJSONObject(index) ?: return@mapNotNull null
            val id=item.optLong("symbolId",0L)
            val name=item.optString("symbolName").ifBlank { item.optString("name") }
            if(id<=0L||name.isBlank())return@mapNotNull null
            BrokerSymbol(id,name)
        }
    }

    suspend fun candles(
        accountId:String,symbolId:Long,period:String,fromMs:Long,toMs:Long,count:Int=1000
    ): List<BrokerCandle> {
        require(period in setOf("M1","M2","M3","M4","M5","M10","M15","M30","H1","H4","H12","D1","W1","MN1"))
        require(fromMs>=0 && toMs>=fromMs && count in 1..1000)
        val array=fetch("/v1/candles",mapOf(
            "accountId" to accountId,"symbolId" to symbolId.toString(),
            "period" to period,"from" to fromMs.toString(),"to" to toMs.toString(),
            "count" to count.toString()
        )).optJSONArray("candles") ?: JSONArray()
        return (0 until array.length()).mapNotNull { index ->
            val item=array.optJSONObject(index) ?: return@mapNotNull null
            if(listOf("timestamp","open","high","low","close","volume").any { !item.has(it) })
                throw java.io.IOException("cTrader returned incomplete candle fields")
            val bar=BrokerCandle(item.getLong("timestamp"),item.getDouble("open"),
                item.getDouble("high"),item.getDouble("low"),item.getDouble("close"),
                item.getLong("volume"))
            if(!listOf(bar.open,bar.high,bar.low,bar.close).all(Double::isFinite) ||
                bar.low<=0 || bar.low>bar.high || bar.open !in bar.low..bar.high ||
                bar.close !in bar.low..bar.high || bar.volume<0 || bar.timestampMs<=0)
                throw java.io.IOException("cTrader returned invalid OHLC candle")
            bar
        }.sortedBy{it.timestampMs}
    }

    suspend fun spot(accountId:String,symbolId:Long):BrokerQuote {
        val quote=fetch("/v1/spot",mapOf("accountId" to accountId,"symbolId" to symbolId.toString()))
        val bid=if(quote.has("bid"))quote.getDouble("bid") else null
        val ask=if(quote.has("ask"))quote.getDouble("ask") else null
        if (bid == null && ask == null) throw IllegalStateException("No cTrader quote received")
        return BrokerQuote(bid,ask,if(quote.has("timestamp"))quote.getLong("timestamp") else null)
    }

    /** Smoke test: does this broker actually expose gold on the user's authorized account? */
    suspend fun goldCheck():String {
        val account=accounts().firstOrNull()
            ?: return "تم الربط ولكن لا توجد حسابات مرخصة لعرض بيانات السوق."
        val gold=symbols(account.accountId).firstOrNull {
            val normalized=it.name.uppercase().replace("/","").replace(" ","")
            normalized.startsWith("XAUUSD") || normalized=="GOLD"
        } ?: return "لم يعرض وسيط هذا الحساب رمز الذهب XAUUSD."
        val quote=spot(account.accountId,gold.symbolId)
        val bid=quote.bid ?: throw IllegalStateException("لم يصل Bid من cTrader")
        val ask=quote.ask ?: throw IllegalStateException("لم يصل Ask من cTrader")
        val time=quote.timestamp ?: throw IllegalStateException("لم يصل توقيت سعر الوسيط")
        val tick=com.example.core.model.Tick("XAUUSD",bid,ask,(bid+ask)/2.0,time,"CTRADER_REST")
        if(!com.example.core.market.VerifiedMarketQuote.isVerified(tick,"XAUUSD"))
            throw IllegalStateException("السعر قديم أو السوق مغلق")
        return "سعر cTrader المؤكد ("+gold.name+"): Bid="+bid+" / Ask="+ask
    }
}
