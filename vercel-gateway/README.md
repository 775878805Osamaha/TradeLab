# TradeLab cTrader — one free hosting provider, no separate database

This is a **Vercel Node.js Function** that provides HTTPS OAuth, read-only cTrader market queries and WebSocket spot streaming. Each TradeLab user authorizes their **own** cTrader account with `scope=accounts`; the app never sends live trades.

## What is simpler?

Unlike the earlier `backend/` design, this gateway does **not** require Railway, Render, Neon, or PostgreSQL. It stores an AES-256-GCM-encrypted session envelope in Android Keystore, so the server needs no database for basic authorization.

Vercel made WebSocket Functions generally available on October 20, 2026. However, **Vercel Hobby limits still apply**: live streams can disconnect at maximum function duration, quota caps and restarts. The Android app must reconnect; no free service can guarantee uninterrupted 24/7 quotes. No provider redistribution rights are implied.

## Current testing mode: safe health-only validation

The production gateway exposes `GET /healthz` even when authentication is not enabled. It returns
`{ "status": "ok", "configured": true, "authEnabled": false }` if credentials are present but the OAuth security gate is closed.

**OAuth, market data requests, and upstream WebSocket subscriptions are deliberately disabled by default.** No real cTrader account should be connected using the encryption key previously shared in a conversation. `CTRADER_AUTH_ENABLED=true` must only be set by the operator after rotating to a fresh, undisclosed 32-byte `SESSION_ENCRYPTION_KEY` and re-testing the release. Until then the Android Settings screen can safely probe the HTTPS gateway, but keeps its login action disabled.

The Android app's existing market data, Replay, Backtest and paper trading are unaffected. A success response from `/healthz` alone does **not** prove cTrader account authorization or real prices.

## Required one-time configuration

Create a **Vercel Hobby project** from the existing GitHub repository `775878805Osamaha/TradeLab`; its **Root Directory** is `vercel-gateway` and **Framework Preset** is Other/Node.js.

Configure in the Vercel project (Production environment), **never in the APK or GitHub**:

- `CTRADER_CLIENT_ID`: actual Client ID from cTrader Open API portal Credentials (not the numeric app portal ID).
- `CTRADER_CLIENT_SECRET`: actual Client Secret from cTrader portal. Do not share it in a chat.
- `SESSION_ENCRYPTION_KEY`: random 32-byte base64 encoded key. Generate using `openssl rand -base64 32`, or use the assistant-managed Vercel encrypted environment setting.

Once a production domain is assigned, `VERCEL_PROJECT_PRODUCTION_URL` supplies the origin automatically. Optionally set `PUBLIC_BASE_URL` to the exact production HTTPS origin with no trailing slash.

Add this exact cTrader redirect in the Open API portal:

`https://ACTUAL-VERCEL-PRODUCTION-HOST/auth/ctrader/callback`

**Do not add** `tradelab://` as the cTrader portal redirect. cTrader sends the short-lived code to the Vercel HTTPS callback; the HTML completion page then deep-links back to Android.

Finally, build the Android APK with the public origin:

`CTRADER_GATEWAY_URL=https://ACTUAL-VERCEL-PRODUCTION-HOST ./gradlew :app:assembleDebug`

The existing TradeLab Android activity already knows how to receive `tradelab://oauth/ctrader?ticket=...`. Users see "ربط cTrader" in Settings only once `CTRADER_GATEWAY_URL` is configured.

## API

- `GET /healthz` — readiness and configuration status (no secrets).
- `GET /auth/ctrader/start?challenge=...` — browser OAuth start with secure HttpOnly flow cookie.
- `GET /auth/ctrader/callback?code=...` — exchange with server-only Client Secret and Android handoff.
- `POST /auth/ctrader/redeem` — app proves it knows its locally held verifier; receives an encrypted gateway session.
- `GET /v1/session`, `/v1/accounts`, `/v1/symbols`, `/v1/candles`, `/v1/spot` — read-only JSON.
- `GET /v1/stream` — WebSocket; first message `{"type":"subscribe","session":"<sealed-gateway-session>","accountId":"123","symbolId":42}`. It emits `spot` events and optional `session` refresh messages. Client must auto-reconnect on function shutdown.
- `POST /v1/logout` — clears sessions **on the client**. Since the design is stateless, old sealed sessions cannot be individually server-revoked. Users can revoke the cTrader app in cTrader account settings.

All sessions are authenticated-encrypted on the server, and encrypted again at rest on Android. Broker secrets never reach the Android app. No trading/order-modification API is exposed.

## Limits / security trade-offs

- The callback's encrypted handoff ticket is valid for only 2 minutes and is bound to an Android-held random verifier, but **is not strictly one-time** because no database is used. For public/high-value deployments, a persistent single-use ticket store and revocation list are recommended.
- No persistent server-side revocation: a sealed session may be replayed within its validity window if stolen. Use TLS; never print URLs, headers, tickets or tokens in logs, and rotate server key if compromised.
- Market availability, symbol IDs, XAUUSD naming, historical gaps and bid/ask precision are broker-specific. All quotes must be validated on-device; no fictitious prices.
- **Free-tier budgets:** Set Vercel's spend controls/alerts; use conservative historical request limits. Very high-traffic live services may require a paid architecture.
- **Release gate:** Test on a demo cTrader account, test both live/demo endpoint separation, check re-auth and refresh, then opt-in to changing the chart data source. Existing TradeLab chart provider is NOT replaced automatically.

Development checks: `npm install && npm run check && npm test` from `vercel-gateway/`.
