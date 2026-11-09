import test from 'node:test';
import assert from 'node:assert/strict';
import {gunzipSync} from 'node:zlib';
import {encodeTickResponse} from '../tick-response.mjs';

test('large real quote response round-trips losslessly through Android-compatible gzip',async()=>{
  const ticks=Array.from({length:15000},(_,i)=>({timestamp:1710000000000+i,
    price:4050+(i%20)*0.01}));
  const payload={source:'ctrader',quoteType:'bid',hasMore:false,ticks};
  const plain=await encodeTickResponse(payload,'identity');
  const zipped=await encodeTickResponse(payload,'gzip, deflate');
  assert.equal(zipped.headers['Content-Encoding'],'gzip');
  assert.equal(zipped.headers.Vary,'Accept-Encoding');
  assert.ok(zipped.bytes.length < plain.bytes.length/2);
  assert.deepEqual(JSON.parse(gunzipSync(zipped.bytes).toString('utf8')),payload);
});

test('small tick pages remain uncompressed to avoid needless extra work',async()=>{
  const source={source:'ctrader',ticks:[{timestamp:1234,price:4050.05}]};
  const encoded=await encodeTickResponse(source,'gzip');
  assert.equal(encoded.headers['Content-Encoding'],undefined);
  assert.deepEqual(JSON.parse(encoded.bytes.toString()),source);
});

test('unsolicited gzip is never sent to clients without compression support',async()=>{
  const payload={source:'ctrader',ticks:Array.from({length:15000},(_,i)=>({timestamp:i,price:2}))};
  for(const encoding of ['br','gzip;q=0, br','gzip;q=invalid']) {
    const response=await encodeTickResponse(payload,encoding);
    assert.equal(response.headers['Content-Encoding'],undefined);
    assert.deepEqual(JSON.parse(response.bytes.toString('utf8')),payload);
  }
});
