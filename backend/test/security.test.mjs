import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { randomToken, tokenHash, constantTimeEqual, makeCipher } from '../security.mjs';
import { normalizeBar, PERIODS } from '../ctrader.mjs';

test('one-time handoff and session tokens are unguessable URL-safe 256-bit values',()=>{
  const one=randomToken(), two=randomToken();
  assert.match(one,/^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(one,two);
  assert.notEqual(tokenHash(one),one);
  assert.ok(constantTimeEqual(tokenHash(one),tokenHash(one)));
  assert.equal(constantTimeEqual(tokenHash(one),tokenHash(two)),false);
});
test('cTrader access and refresh tokens are authenticated-encrypted at rest',()=>{
  const cipher=makeCipher(randomBytes(32).toString('base64'));
  const value='sensitive-ctrader-token';
  const packed=cipher.encrypt(value);
  assert.ok(!packed.includes(value));
  assert.equal(cipher.decrypt(packed),value);
  const parts=packed.split('.');
  parts[2]=Buffer.from('tampered').toString('base64url');
  assert.throws(()=>cipher.decrypt(parts.join('.')));
});
test('converts cTrader delta-compressed OHLC and timestamps without synthetic prices',()=>{
  assert.deepEqual(normalizeBar({low:250000000,deltaOpen:100000,deltaHigh:300000,deltaClose:200000,utcTimestampInMinutes:30000000,volume:42}),{
    timestamp:1800000000000,open:2501,high:2503,low:2500,close:2502,volume:42
  });
  assert.equal(PERIODS.M3,3);
  assert.equal(PERIODS.W1,13);
});
