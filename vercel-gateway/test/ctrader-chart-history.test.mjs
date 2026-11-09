import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {CTraderGateway} from '../ctrader.mjs';

function socketForTrendbars({accountId='12345',malformed=false,extraOlder=false,conflictingDuplicate=false}={}) {
  const requests=[];
  class BrokerSocket extends EventEmitter {
    constructor(){
      super();
      this.readyState=0;
      queueMicrotask(()=>{this.readyState=1;this.emit('open');});
    }
    send(json,callback=()=>{}) {
      const packet=JSON.parse(json);
      requests.push(packet);
      callback();
      const type={2100:2101,2102:2103,2137:2138}[packet.payloadType];
      const payload=packet.payloadType===2102
        ? {ctidTraderAccountId:12345}
        : packet.payloadType===2137
          ? {ctidTraderAccountId:accountId,period:1,symbolId:42,
             trendbar:[
               ...(extraOlder ? [{
                 utcTimestampInMinutes:29999998,
                 // A malformed older candle outside the requested interval
                 // cannot invalidate genuine bars inside this time window.
                 low:411000000,deltaOpen:200000,deltaHigh:-1,
                 deltaClose:50000,volume:40,
               }] : []),
               {
                 utcTimestampInMinutes:30000000,
                 low:411000000,
                 deltaOpen:0,
                 deltaHigh:malformed? -1:120000,
                 deltaClose:50000,
                 volume:80
               },
               ...(conflictingDuplicate ? [{
                 utcTimestampInMinutes:30000000,
                 low:411000000,deltaOpen:0,deltaHigh:120000,
                 deltaClose:60000,volume:80,
               }] : []),
             ],
             hasMore:false}
          : {};
      queueMicrotask(()=>this.emit('message',Buffer.from(JSON.stringify({
        clientMsgId:packet.clientMsgId,payloadType:type,payload,
      }))));
    }
    close(){this.readyState=3;this.emit('close');}
  }
  return {socket:new BrokerSocket(),requests};
}

test('gold M1 trendbars have verified cTrader account, symbol and period',async()=>{
  const {socket,requests}=socketForTrendbars();
  const client=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  const from=30000000*60000-60000;
  const to=30000000*60000+60000;
  try {
    const result=await client.channel(false).history(
      12345,'readonly',42,1,from,to,1000);
    assert.equal(result.candles.length,1);
    assert.equal(result.candles[0].timestamp,30000000*60000);
    assert.equal(result.candles[0].low,4110);
    assert.equal(result.candles[0].high,4111.2);
    assert.equal(result.candles[0].close,4110.5);
    const request=requests.find(p=>p.payloadType===2137);
    assert.equal(request.payload.ctidTraderAccountId,12345);
    assert.equal(request.payload.symbolId,42);
    assert.equal(request.payload.period,1);
  } finally {socket.close();}
});

test('trendbar response for a different cTrader account is never displayed',async()=>{
  const {socket}=socketForTrendbars({accountId:'99999'});
  const client=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    await assert.rejects(client.channel(false).history(
      12345,'readonly',42,1,30000000*60000-60000,
      30000000*60000+60000,1000),/ctrader_trendbar_provenance_mismatch/);
  } finally {socket.close();}
});

test('invalid cTrader gold trendbars cannot reach the chart',async()=>{
  const {socket}=socketForTrendbars({malformed:true});
  const client=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    await assert.rejects(client.channel(false).history(
      12345,'readonly',42,1,30000000*60000-60000,
      30000000*60000+60000,1000),/invalid_ctrader_trendbar/);
  } finally {socket.close();}
});

test('valid broker bar outside requested time window does not cause HTTP 400',async()=>{
  const {socket}=socketForTrendbars({extraOlder:true});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const center=30000000*60000;
    const data=await gateway.channel(false).history(
      12345,'readonly',42,1,center-60000,center+60000,900);
    assert.deepEqual(data.candles.map(c=>c.timestamp),[center]);
    assert.equal(data.candles[0].close,4110.5);
  } finally {socket.close();}
});

test('conflicting duplicate broker bar remains a hard source error',async()=>{
  const {socket}=socketForTrendbars({conflictingDuplicate:true});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const center=30000000*60000;
    await assert.rejects(gateway.channel(false).history(
      12345,'readonly',42,1,center-60000,center+60000,900),
      /invalid_ctrader_trendbar_timestamps/);
  } finally {socket.close();}
});
