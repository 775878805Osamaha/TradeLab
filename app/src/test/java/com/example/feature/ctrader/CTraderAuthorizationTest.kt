package com.example.feature.ctrader

import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class CTraderAuthorizationTest {
    @Test fun browserAuthorizationRequestsReadOnlyScope() {
        val url=CTraderAuthorization.authorizationUrl()
        assertEquals("https",url.scheme)
        assertEquals("id.ctrader.com",url.host)
        assertEquals("46509",url.getQueryParameter("client_id"))
        assertEquals("accounts",url.getQueryParameter("scope"))
        assertEquals(CTraderAuthorization.REDIRECT_URI,url.getQueryParameter("redirect_uri"))
        assertNull(url.getQueryParameter("client_secret"))
    }

    @Test fun callbackOnlyAcceptsRegisteredAndroidDeepLink() {
        assertTrue(CTraderAuthorization.isCallback(Uri.parse("tradelab://oauth/ctrader?code=example")))
        assertFalse(CTraderAuthorization.isCallback(Uri.parse("https://oauth/ctrader?code=example")))
        assertFalse(CTraderAuthorization.isCallback(Uri.parse("tradelab://other/ctrader?code=example")))
        assertNull(CTraderAuthorization.callbackStatus(Uri.parse("tradelab://other/ctrader?code=example")))
    }

    @Test fun callbackDoesNotClaimMarketDataConnected() {
        val message=CTraderAuthorization.callbackStatus(Uri.parse("tradelab://oauth/ctrader?code=example"))
        assertNotNull(message)
        assertTrue(message!!.contains("لم يتم تفعيل الأسعار"))
    }
}
