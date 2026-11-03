-- Apply once to a managed PostgreSQL database before running the gateway.
CREATE TABLE IF NOT EXISTS oauth_flows (
  browser_hash TEXT PRIMARY KEY,
  verifier_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS ctrader_sessions (
  id UUID PRIMARY KEY,
  session_hash TEXT UNIQUE,
  access_cipher TEXT NOT NULL,
  refresh_cipher TEXT NOT NULL,
  token_expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS oauth_handoffs (
  ticket_hash TEXT PRIMARY KEY,
  verifier_hash TEXT NOT NULL,
  session_id UUID NOT NULL REFERENCES ctrader_sessions(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS ctrader_sessions_active_idx ON ctrader_sessions(session_hash) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS oauth_handoffs_expiry_idx ON oauth_handoffs(expires_at);
CREATE INDEX IF NOT EXISTS oauth_flows_expiry_idx ON oauth_flows(expires_at);
