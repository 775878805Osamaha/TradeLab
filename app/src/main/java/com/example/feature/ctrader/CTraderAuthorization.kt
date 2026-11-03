package com.example.feature.ctrader

import android.content.Context
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.example.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.concurrent.TimeUnit

/**
 * cTrader browser sign-in: Android never receives the broker token or app Client Secret.
 * The backend verifies the browser callback, exchanges the short-lived code and sends
 * a one-time handoff ticket. An app-held verifier binds the ticket to the initiating device.
 */
object CTraderAuthorization {
    private const val PREFS = "ctrader_auth_v2"
    private const val KEYSTORE_ALIAS = "tradelab_ctrader_session_v1"
    private const val VERIFIER = "pending_verifier"
    private const val SESSION = "encrypted_session"
    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .build()

    val gatewayBase: String
        get() = BuildConfig.CTRADER_GATEWAY_URL.trimEnd('/')

    val isConfigured: Boolean
        get() {
            val uri = Uri.parse(gatewayBase)
            return uri.scheme == "https" && !uri.host.isNullOrBlank() &&
                uri.port == -1 && uri.path.orEmpty().isEmpty() &&
                uri.query == null && uri.fragment == null && uri.userInfo == null
        }

    data class GatewayCheck(val reachable: Boolean, val authEnabled: Boolean, val message: String)

    /** Public non-credential probe; safe to use before anybody signs into cTrader. */
    suspend fun checkGateway(): GatewayCheck = withContext(Dispatchers.IO) {
        if (!isConfigured) return@withContext GatewayCheck(false, false, "رابط خدمة cTrader غير مهيأ.")
        try {
            val request = Request.Builder().url(gatewayBase + "/healthz")
                .header("Accept", "application/json").build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext GatewayCheck(false,false,
                    "خدمة cTrader لا تستجيب حاليًا (HTTP ${response.code}).")
                val result = JSONObject(response.body?.string().orEmpty())
                if(result.optString("status") != "ok" ||
                   result.optString("service") != "TradeLab cTrader OAuth gateway")
                    return@withContext GatewayCheck(false,false,"استجابة خدمة غير متوقعة.")
                if(!result.optBoolean("configured",false))
                    return@withContext GatewayCheck(true,false,"الخدمة تعمل ولكن إعدادات cTrader غير مكتملة.")
                if(!result.optBoolean("authEnabled",false))
                    return@withContext GatewayCheck(true,false,
                        "خادم TradeLab يعمل بنجاح. تسجيل دخول cTrader متوقف مؤقتًا لحماية الجلسات.")
                GatewayCheck(true,true,"الخادم يستجيب ومهيأ لتسجيل الدخول بصلاحية القراءة فقط.")
            }
        } catch (_: Exception) {
            GatewayCheck(false,false,"تعذر الاتصال بخدمة cTrader، تحقق من الإنترنت.")
        }
    }

    // The browser sets its own HttpOnly flow cookie; no OAuth code is handled by Android.
    fun authorizationUrl(context: Context): Uri? {
        if (!isConfigured) return null
        val verifier = randomBase64Url()
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.UTF_8))
        val challenge = Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        if (!context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(VERIFIER, verifier).commit()) return null
        return Uri.parse(gatewayBase + "/auth/ctrader/start").buildUpon()
            .appendQueryParameter("challenge", challenge).build()
    }

    fun isCallback(uri: Uri?): Boolean =
        uri?.scheme == "tradelab" && uri.host == "oauth" && uri.path == "/ctrader"

    fun callbackStatus(uri: Uri?): String? {
        if (!isCallback(uri)) return null
        return if (uri?.getQueryParameter("ticket")?.isNotBlank() == true)
            "جارٍ إكمال ربط cTrader بشكل آمن…"
        else "لم يصل تأكيد ربط صالح من cTrader."
    }

    suspend fun redeem(context: Context, uri: Uri?): String = withContext(Dispatchers.IO) {
        if (!isConfigured) return@withContext "خدمة تسجيل الدخول لم تُفعّل بعد."
        if (!isCallback(uri)) return@withContext "رابط عودة cTrader غير صحيح."
        val ticket = uri?.getQueryParameter("ticket")
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val verifier = preferences.getString(VERIFIER, null)
        if (ticket.isNullOrBlank() || verifier.isNullOrBlank()) {
            return@withContext "انتهت محاولة الربط. افتح تسجيل الدخول مرة أخرى من الإعدادات."
        }
        try {
            val json = JSONObject().put("ticket", ticket).put("verifier", verifier)
            val request = Request.Builder()
                .url(gatewayBase + "/auth/ctrader/redeem")
                .post(json.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext "تعذر تأكيد الربط. أعد المحاولة."
                val data = JSONObject(response.body?.string().orEmpty())
                val sessionToken = data.optString("sessionToken")
                if (!isSealedGatewaySession(sessionToken)) {
                    return@withContext "استجابة جلسة غير صالحة."
                }
                saveSession(context, sessionToken)
                preferences.edit().remove(VERIFIER).apply()
                return@withContext "تم ربط cTrader بصلاحية القراءة فقط. لم يتم تفعيل مصدر الأسعار على الشارت بعد."
            }
        } catch (_: Exception) {
            return@withContext "تعذر الاتصال بخدمة TradeLab الآمنة. تحقق من الإنترنت وحاول مجددًا."
        }
    }

    private fun isSealedGatewaySession(value: String): Boolean =
        value.length in 100..6144 &&
            Regex("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$").matches(value)

    fun isLinked(context: Context): Boolean = !readSession(context).isNullOrEmpty()

    internal fun sessionForReadOnlyRequests(context: Context): String? = readSession(context)

    internal fun rotateSession(context: Context, token: String) {
        if (isSealedGatewaySession(token)) saveSession(context, token)
    }

    suspend fun accountSummary(context: Context): String = withContext(Dispatchers.IO) {
        val sessionToken = readSession(context) ?: return@withContext "لم يتم ربط حساب cTrader بعد."
        if (!isConfigured) return@withContext "خادم cTrader غير مهيأ."
        try {
            val request = Request.Builder().url(gatewayBase + "/v1/accounts")
                .header("Authorization", "Bearer $sessionToken").build()
            client.newCall(request).execute().use { response ->
                response.header("X-TradeLab-Session")?.let { rotateSession(context, it) }
                if (response.code == 401) return@withContext "انتهت صلاحية جلسة TradeLab؛ سجل الدخول مجددًا."
                if (!response.isSuccessful) return@withContext "تعذر استرجاع حسابات cTrader الآن."
                val accounts = JSONObject(response.body?.string().orEmpty()).optJSONArray("accounts")
                return@withContext if (accounts == null || accounts.length() == 0)
                    "تم الربط، لكن لم تظهر حسابات cTrader مرخصة لهذا المستخدم."
                else "الحسابات المتاحة للقراءة: ${accounts.length()}"
            }
        } catch (_: Exception) {
            return@withContext "تعذر الاتصال بخدمة TradeLab الآن."
        }
    }

    private fun randomBase64Url(): String {
        val bytes = ByteArray(32).also(SecureRandom()::nextBytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEYSTORE_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }

    private fun saveSession(context: Context, token: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        val output = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        val packed = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(output, Base64.NO_WRAP)
        check(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(SESSION, packed).commit())
    }

    private fun readSession(context: Context): String? {
        return try {
        val packed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(SESSION, null)
            ?: return null
        val parts = packed.split(':')
        if (parts.size != 2) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        }
        String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) { null }
    }
}
