# TradeLab cTrader Gateway (per-user, read only)

This is an **always-on Node.js + PostgreSQL** gateway for the existing Android TradeLab app.
Every TradeLab user authorizes **their own cTrader ID**. The OAuth scope is **accounts** (read-only).
**No cTrader Client Secret or broker access/refresh token is embedded in APKs.**
This service exposes a strict allowlist of read-only Open API message IDs. Trading and Replay remain virtual inside TradeLab.

## Zero-cost prototype with Render + Neon (November 2026)

The repository root includes a `render.yaml` Blueprint selecting the **Free** web-service plan explicitly; it does **not** provision Render Postgres (which expires after 30 days). Use a **Neon Free** PostgreSQL database instead. Note the Render Free service sleeps after 15 minutes without inbound requests and can take about a minute to cold-start. Market feed continuity is not guaranteed, so **do not advertise this setup as 24/7 production market data**.

1. Create a Neon Free project, then copy its PostgreSQL connection URL with `sslmode=require` **privately** (never paste it into public chat or GitHub).
2. On Render, deploy this repo's `feat/chart-gesture-stability-20261031` branch using the root `render.yaml` Blueprint. Keep the service plan at `free`. The `rootDir` is `backend`.
3. Set `DATABASE_URL` to the Neon URL, and `CTRADER_CLIENT_ID` and `CTRADER_CLIENT_SECRET` to the **actual cTrader Open API application credentials** in Render's encrypted environment settings. Do not assume that the numeric portal app ID is the OAuth client ID. Render generates the random `TOKEN_ENCRYPTION_KEY`.
4. The server automatically creates the PostgreSQL tables from `schema.sql` before listening. No Render shell access or paid Render database is needed.
5. Once Render assigns an actual `https://...onrender.com` hostname, add its exact callback `https://...onrender.com/auth/ctrader/callback` to the cTrader Open API portal. The gateway reads Render's `RENDER_EXTERNAL_URL` environment variable automatically.
6. Build Android with `CTRADER_GATEWAY_URL=https://...onrender.com`. A new APK is required after the URL is known. Test with a demo cTrader account and verify its available symbols and XAUUSD data before switching chart providers.

**Cost safeguard:** Do not select a paid Render instance, do not create a paid Neon project, and do not add automatic paid upgrades. Free quotas may suspend service rather than guarantee capacity. If Render/Neon ask for billing details, review them before proceeding.

## Why an always-on container rather than serverless functions?

Open API's spot/live-candle feed is a long-lived WebSocket on port 5036 (JSON). A standard serverless function is not an appropriate host for those sessions. Deploy this container on an always-on service supporting outbound WebSocket connections on ports 5036 (e.g. a suitable Render/Railway/Fly.io service), behind its managed HTTPS endpoint and a managed PostgreSQL database. Production data availability depends on the user's broker permissions and the symbol list.

## Deployment requirements

Set these **server-side secrets** in the hosting dashboard, never in GitHub or ChatGPT:

- `PUBLIC_BASE_URL` (optional override on Render; required elsewhere): the full **deployed HTTPS origin** (for example `https://your-owned-gateway.example.com`), with no path; it must match the HTTPS redirect allowed in cTrader.
- `DATABASE_URL`: TLS-capable PostgreSQL database URL from the hosting provider.
- `CTRADER_CLIENT_ID`: your approved cTrader app client ID (not necessarily the app's numeric portal ID).
- `CTRADER_CLIENT_SECRET`: confidential value from cTrader Open API portal.
- `TOKEN_ENCRYPTION_KEY`: fresh random base64-encoded 32-byte key (generate locally with `openssl rand -base64 32`). **Back up securely; changing it invalidates encrypted tokens.**
- `PORT`: optional, injected by the host; default 8080.

The gateway automatically applies `backend/schema.sql` on startup; the database user needs permission to create these tables. Configure database TLS using your hosting provider's standard URL/CA bundle and verify its certificate; do not disable TLS verification.

In the **cTrader Open API portal** add exactly:
`https://YOUR-DEPLOYED-GATEWAY-HOST/auth/ctrader/callback`
Do **not** use `tradelab://` as the portal redirect; cTrader rejects non-HTTPS URLs.
Do **not** use the default `openapi.ctrader.com/apps/...` playground redirect for production.
The existing `chatgpt.site` landing page requires no modifications.

Build Android with the public HTTPS gateway origin:
`CTRADER_GATEWAY_URL=https://YOUR-DEPLOYED-GATEWAY-HOST ./gradlew :app:assembleDebug`
The Android login button stays disabled until a gateway origin is configured. All secrets stay only on the gateway. Rebuild the APK after setting the domain.

## OAuth / Android handoff

1. Android securely generates a random **device verifier** and passes only its SHA-256 challenge to `GET /auth/ctrader/start?challenge=...`.
2. Browser receives a 10-minute HttpOnly Secure SameSite=Lax flow cookie. The gateway redirects to the real cTrader permission page with **scope=accounts**.
3. cTrader redirects to the **server HTTPS callback** with a short-lived code (expires in about 60 seconds). Gateway checks the initiating browser cookie, atomically consumes the flow, exchanges the code using server-side credentials and stores **AES-256-GCM encrypted** broker tokens in PostgreSQL.
4. Gateway returns a 2-minute one-time handoff ticket via the `tradelab://oauth/ctrader?ticket=...` Android deep link. If browser blocks auto-opening, the HTML page provides an explicit "Open TradeLab" button.
5. Android redeems the ticket via `POST /auth/ctrader/redeem` with its original verifier. The gateway atomically checks the verifier hash and marks the ticket consumed. It returns **only a new random gateway session token**, never broker credentials. Android encrypts this session token with the Android Keystore.
6. `GET /v1/session`, `GET /v1/accounts`, `GET /v1/symbols?accountId=...`, `GET /v1/candles?accountId=...&symbolId=...&period=M1&from=...&to=...&count=1000`, and `GET /v1/spot?accountId=...&symbolId=...` require `Authorization: Bearer <gateway-session-token>`. `POST /v1/logout` revokes it.

Only accounts granted through the current user session may be accessed. Server verifies `SCOPE_VIEW` before exposing accounts. The cTrader transport uses app auth and account auth, and denies all order-modification payload types. It maintains one upstream connection each for live and demo.

## Operational safeguards / rollout

- **Do not enable the new provider as a chart default until a real cTrader account/market-data smoke test passes.** Existing chart/replay/results providers are not replaced in this changeset.
- Verify one demo user, no accounts, multiple accounts, XAUUSD naming by broker, live/demo, market closed, disconnect/reconnect, token expiration/refresh, and historical window edge cases.
- Rate limit and protect gateway traffic at the hosting edge (WAF/IP controls). Add external monitoring and alerts.
- Set access logs to **exclude full OAuth URLs and Authorization headers**. Never log codes, tickets, tokens, secrets, or account identifiers.
- Single gateway container + managed DB is the initial scalable architecture. Before launching publicly, add load tests, a shared rate limiter and a cache/queue for heavy historical candle workloads.
- Live ticks and bar history availability depend on cTrader broker permissions; no synthetic prices are generated.

Local verification: `cd backend && npm install && npm test && npm run check`. Full live integration tests require valid deployment credentials and a consenting demo cTrader account.
