# TradeLab cTrader — one free hosting provider, no separate database

This is a **Vercel Node.js Function** that provides HTTPS OAuth, read-only cTrader market queries and WebSocket spot streaming. Each TradeLab user authorizes their **own** cTrader account with `scope=accounts`; the app never sends live trades.

## What is simpler?

Unlike the earlier `backend/` design, this gateway does **not** require Railway, Render, Neon, or PostgreSQL. It stores an AES-256-GCM-encrypted session envelope in Android Keystore, so the server needs no database for basic authorization.

Vercel made WebSocket Functions generally available on October 20, 2026. However, **Vercel Hobby limits still apply**: live streams can disconnect at maximum function duration, quota caps and restarts. The Android app must reconnect; no free service can guarantee uninterrupted 24/7 quotes. No provider redistribution rights are implied.

## Key derivation and safe rollout (November 2026)

`SESSION_ENCRYPTION_KEY` is treated as a 32-byte **HKDF salt**, not the standalone AES key. The actual 256-bit AES-GCM session key is derived with HKDF-SHA256 from the private `CTRADER_CLIENT_SECRET`, this salt, and a versioned domain-separation string. A salt previously revealed in chat is therefore **not sufficient to decrypt broker sessions**, as long as the cTrader Client Secret remains confidential and sufficiently random. No action to change the salt is required for this design.

When all three environment settings are present, `/healthz` reports `configured:true, authEnabled:true`; the Android app uses it to enable browser sign-in. An operator can disable all OAuth/market data endpoints by setting `CTRADER_AUTH_ENABLED=false` on Vercel. Health remains accessible while disabled.

Existing sessions made with the earlier, un-derived encryption key will not decrypt in the updated service and users must sign in again. A successful health check confirms only that the gateway is responding; it does not prove account authorization or actual XAUUSD availability.

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

The Android application currently uses the public HTTPS origin
`https://tradelab-vercel-gateway.vercel.app` (never a broker secret). Build with
`./gradlew :app:assembleDebug`; ensure the deployed gateway's OAuth callback is registered in cTrader.
The Android activity receives `tradelab://oauth/ctrader?ticket=...`, redeems the
verifier-bound ticket, encrypts the session at rest, and lets each user choose an
authorized demo/live account in Settings. Gold/forex Chart, Replay and Backtest
are routed through cTrader; BTC/ETH remain Binance-only. No fallback market feed
is used if cTrader is unavailable.

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
- **Release gate:** The Android routing is implemented but must still be tested with a
  real authorized demo account: browser callback, broker symbols, XAUUSD trendbars,
  historical paging/Replay, reconnects, session refresh and account-switch safety.
  Gateway health alone does not prove broker data availability. Keep PR #403 unmerged
  until these checks and Android CI pass.

Development checks: `npm install && npm run check && npm test` from `vercel-gateway/`.
