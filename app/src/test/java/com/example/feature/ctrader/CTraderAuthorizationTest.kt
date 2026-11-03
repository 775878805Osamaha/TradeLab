package com.example.feature.ctrader

import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class CTraderAuthorizationTest {
    @Test fun callbackOnlyAcceptsRegisteredNativeTicketLink() {
        assertTrue(CTraderAuthorization.isCallback(Uri.parse("tradelab://oauth/ctrader?ticket=example")))
        assertFalse(CTraderAuthorization.isCallback(Uri.parse("https://oauth/ctrader?ticket=example")))
        assertFalse(CTraderAuthorization.isCallback(Uri.parse("tradelab://other/ctrader?ticket=example")))
        assertNull(CTraderAuthorization.callbackStatus(Uri.parse("tradelab://other/ctrader?ticket=example")))
    }

    @Test fun callbackNeverClaimsBrokerConnectedBeforeTicketRedeemed() {
        val message=CTraderAuthorization.callbackStatus(Uri.parse("tradelab://oauth/ctrader?ticket=example"))
        assertNotNull(message)
        assertTrue(message!!.contains("جارٍ إكمال"))
        assertFalse(message.contains("تم ربط"))
    }

    @Test fun reachableGatewayWithAuthenticationPausedDoesNotEnableSignIn() {
        val health = CTraderAuthorization.parseGatewayHealth(
            """{"status":"ok","service":"TradeLab cTrader OAuth gateway","configured":true,"authEnabled":false}"""
        )
        assertTrue(health.reachable)
        assertFalse(health.authEnabled)
        assertTrue(health.message.contains("متوقف"))
    }

    @Test fun malformedOrUntrustedHealthResponseNeverEnablesSignIn() {
        val health = CTraderAuthorization.parseGatewayHealth(
            """{"status":"ok","service":"Untrusted Gateway","configured":true,"authEnabled":true}"""
        )
        assertFalse(health.reachable)
        assertFalse(health.authEnabled)
    }

    @Test fun authorizationEnabledRequiresExplicitTrustedReadiness() {
        val health = CTraderAuthorization.parseGatewayHealth(
            """{"status":"ok","service":"TradeLab cTrader OAuth gateway","configured":true,"authEnabled":true}"""
        )
        assertTrue(health.reachable)
        assertTrue(health.authEnabled)
    }

    @Test fun unsupportedDirectCodeCallbackCannotSignIn() {
        val message=CTraderAuthorization.callbackStatus(Uri.parse("tradelab://oauth/ctrader?code=example"))
        assertTrue(message!!.contains("لم يصل تأكيد"))
    }
}
