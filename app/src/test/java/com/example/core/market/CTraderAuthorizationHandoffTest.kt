package com.example.core.market

import android.app.Application
import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], application = Application::class)
class CTraderAuthorizationHandoffTest {
    private fun gateway() = CTraderGatewayClient(RuntimeEnvironment.getApplication())

    @Test fun browserStartsOnlyOnConfiguredHttpsGatewayWithOpaqueChallenge() {
        val url = Uri.parse(gateway().beginAuthorization())
        assertEquals("https", url.scheme)
        assertEquals("tradelab-vercel-gateway.vercel.app", url.host)
        assertEquals("/auth/ctrader/start", url.path)
        assertTrue(url.getQueryParameter("challenge")!!.matches(Regex("[A-Za-z0-9_-]{43}")))
        assertNull(url.getQueryParameter("verifier"))
        assertNull(url.getQueryParameter("client_secret"))
    }

    @Test fun callbackRejectsForeignOriginsAndInvalidTickets() {
        val client = gateway()
        assertTrue(client.isCallback(Uri.parse("tradelab://oauth/ctrader?ticket=one.two.three")))
        assertFalse(client.isCallback(Uri.parse("https://oauth/ctrader?ticket=one.two.three")))
        assertFalse(client.isCallback(Uri.parse("tradelab://other/ctrader?ticket=one.two.three")))
        assertFalse(client.isCallback(Uri.parse("tradelab://oauth/ctrader?code=not-a-ticket")))
    }
}
