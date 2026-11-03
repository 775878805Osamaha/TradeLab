package com.example.core.market

import org.junit.Assert.*
import org.junit.Test

class CTraderGatewayErrorsTest {
    @Test fun brokerTimeoutIsDistinguishedFromTokenOrPermissionErrors() {
        val timeout = CTraderGatewayErrors.explain(503, "ctrader_response_timeout")
        val exchange = CTraderGatewayErrors.explain(503, "ctrader_token_exchange_failed")
        assertTrue(timeout.contains("مهلة"))
        assertTrue(exchange.contains("تفويض"))
        assertNotEquals(timeout, exchange)
    }

    @Test fun unknownOrMaliciousErrorContentIsNeverReflectedIntoUserMessage() {
        val payload = "token=<secret>"
        val description = CTraderGatewayErrors.explain(503, payload)
        assertFalse(description.contains(payload))
        assertTrue(description.contains("HTTP 503"))
    }

    @Test fun gatewayErrorRetainsNonSecretCategoryForSupport() {
        val error = CTraderGatewayException(503, "ctrader_connection_failed")
        assertEquals(503, error.statusCode)
        assertTrue(error.message.orEmpty().contains("ctrader_connection_failed"))
    }
}
