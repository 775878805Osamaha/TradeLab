import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {CTraderGateway} from '../ctrader.mjs';

function socketForTrendbars({accountId='12345',malformed=false,extraOlder=false,conflictingDuplicate=false,adaptiveMode=null,barMinutes=30000000}={}) {
  const requests=[];
  let historicalRequests=0;
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
      const firstTrendbar=packet.payloadType===2137 && ++historicalRequests===1;
      const rejected=(adaptiveMode==='boundary_always' && packet.payloadType===2137) ||
        (firstTrendbar && ['boundary','boundary_older','unauthorized'].includes(adaptiveMode));
      const type=rejected?2142:{2100:2101,2102:2103,2137:2138}[packet.payloadType];
      const payload=rejected
        ? {errorCode:adaptiveMode==='unauthorized'?'ACCOUNT_NOT_AUTHORIZED':'INCORRECT_BOUNDARIES'}
        : packet.payloadType===2102
        ? {ctidTraderAccountId:12345}
        : packet.payloadType===2137
          ? {ctidTraderAccountId:accountId,period:packet.payload.period,symbolId:42,
             trendbar:[
               ...(extraOlder ? [{
                 utcTimestampInMinutes:29999998,
                 // A malformed older candle outside the requested interval
                 // cannot invalidate genuine bars inside this time window.
                 low:411000000,deltaOpen:200000,deltaHigh:-1,
                 deltaClose:50000,volume:40,
               }] : []),
               {
                 utcTimestampInMinutes:barMinutes,
                 low:411000000,
                 deltaOpen:0,
                 deltaHigh:malformed? -1:120000,
                 deltaClose:50000,
                 volume:80
               },
               ...(conflictingDuplicate ? [{
                 utcTimestampInMinutes:barMinutes,
                 low:411000000,deltaOpen:0,deltaHigh:120000,
                 deltaClose:60000,volume:80,
               }] : []),
             ],
             hasMore:firstTrendbar && adaptiveMode==='truncated'}
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

test('cTrader boundary rejection retries once with documented count-back request',async()=>{
  const {socket,requests}=socketForTrendbars({adaptiveMode:'boundary'});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  const center=30000000*60000;
  try {
    const data=await gateway.channel(false).history(
      12345,'readonly',42,1,center-180000,center+60000,900);
    assert.equal(data.queryMode,'count_back');
    assert.deepEqual(data.candles.map(c=>c.timestamp),[center]);
    assert.equal(data.candles[0].close,4110.5);
    const reqs=requests.filter(p=>p.payloadType===2137).map(p=>p.payload);
    assert.equal(reqs.length,2);
    assert.equal(reqs[0].fromTimestamp,center-180000);
    assert.equal(reqs[0].toTimestamp,center+60000);
    assert.equal(Object.hasOwn(reqs[1],'fromTimestamp'),false);
    assert.equal(reqs[1].toTimestamp,center+60000);
    assert.equal(reqs[1].count,900);
  } finally {socket.close();}
});

test('count-back preserves older verified broker bars during a closed market',async()=>{
  const center=30000000*60000;
  const weekendBar=30000000-2*24*60;
  const {socket,requests}=socketForTrendbars({
    adaptiveMode:'boundary_older',barMinutes:weekendBar,
  });
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const result=await gateway.channel(false).history(
      12345,'readonly',42,1,center-900000,center+60000,900);
    assert.equal(result.queryMode,'count_back');
    assert.deepEqual(result.candles.map(c=>c.timestamp),[weekendBar*60000]);
    assert.equal(requests.filter(p=>p.payloadType===2137).length,2);
  } finally {socket.close();}
});

test('count-back never weakens cTrader account provenance validation',async()=>{
  const {socket}=socketForTrendbars({accountId:'99999',adaptiveMode:'boundary'});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const center=30000000*60000;
    await assert.rejects(gateway.channel(false).history(
      12345,'readonly',42,1,center-900000,center+60000,900),
      /ctrader_trendbar_provenance_mismatch/);
  } finally {socket.close();}
});

test('a broker rejecting both request forms ends after two requests, never inventing OHLC',async()=>{
  const {socket,requests}=socketForTrendbars({adaptiveMode:'boundary_always'});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const center=30000000*60000;
    await assert.rejects(gateway.channel(false).history(
      12345,'readonly',42,1,center-900000,center+60000,900),
      error=>error.brokerCode==='INCORRECT_BOUNDARIES');
    assert.equal(requests.filter(p=>p.payloadType===2137).length,2);
  } finally {socket.close();}
});

test('a capped cTrader broker page is usable as incomplete chart history',async()=>{
  const {socket,requests}=socketForTrendbars({adaptiveMode:'truncated'});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  const center=30000000*60000;
  try {
    const data=await gateway.channel(false).history(
      12345,'readonly',42,1,center-120000,center+120000,900);
    assert.equal(data.hasMore,true);
    assert.deepEqual(data.candles.map(c=>c.timestamp),[center]);
    assert.equal(requests.filter(p=>p.payloadType===2137).length,1);
  } finally {socket.close();}
});

test('wide 89-day M3 and M15 chart pages do not exhaust the history call budget',async()=>{
  const from=30000000*60000-89*86400000;
  const to=30000000*60000+60000;
  for(const period of [3,7]) {
    const {socket,requests}=socketForTrendbars({adaptiveMode:'truncated'});
    const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
    try {
      const page=await gateway.channel(false).history(
        12345,'readonly',42,period,from,to,1000);
      assert.equal(page.hasMore,true);
      assert.equal(page.candles.length,1);
      assert.equal(requests.filter(p=>p.payloadType===2137).length,1);
    } finally {socket.close();}
  }
});

test('account authorization failure must not trigger a hidden history retry',async()=>{
  const {socket,requests}=socketForTrendbars({adaptiveMode:'unauthorized'});
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  const center=30000000*60000;
  try {
    await assert.rejects(gateway.channel(false).history(
      12345,'readonly',42,1,center-120000,center+120000,900),
      error=>error.brokerCode==='ACCOUNT_NOT_AUTHORIZED');
    assert.equal(requests.filter(p=>p.payloadType===2137).length,1);
  } finally {socket.close();}
});
