import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { sealedCodec, hash, randomToken, constantTimeMatch } from '../session.mjs';

test('client verifier challenge is URL safe and 256-bit',()=>{
  const token=randomToken();
  assert.match(token,/^[A-Za-z0-9_-]{43}$/);
  assert.match(hash(token),/^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(hash(token),token);
});
test('server-side AES-GCM seals tokens; tampering fails closed',()=>{
  const codec=sealedCodec(randomBytes(32).toString('base64'));
  const s=codec.seal({type:'session',access:'ctrader-secret-value',scope:'accounts'});
  assert.equal(s.includes('ctrader-secret-value'),false);
  assert.equal(codec.open(s).access,'ctrader-secret-value');
  const last=s.slice(-1)==='A'?'B':'A';
  assert.throws(()=>codec.open(s.slice(0,-1)+last));
});
test('handoff verifier must match SHA-256 challenge',()=>{
  const verifier=randomToken(),challenge=hash(verifier);
  assert.ok(constantTimeMatch(challenge,hash(verifier)));
  assert.equal(constantTimeMatch(challenge,hash(randomToken())),false);
});
test('key mismatch and malformed ciphertext rejected',()=>{
  assert.throws(()=>sealedCodec('incorrect'),/32 bytes/);
  const codec=sealedCodec(randomBytes(32).toString('base64'));
  assert.throws(()=>codec.open('not.a.sealed.token'));
});
