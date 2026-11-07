import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {CTraderGateway, normalizeHistoricalBidTicks} from '../ctrader.mjs';

test('cTrader newest-first tick deltas become genuine chronological bid prices',()=>{
  assert.deepEqual(normalizeHistoricalBidTicks([
    {timestamp:1010,tick:200050000},
    {timestamp:-7,tick:-10000},
    {timestamp:0,tick:-10000},
    {timestamp:-3,tick:-10000},
  ],1000,1010),[
    {timestamp:1000,price:2000.2},
    {timestamp:1003,price:2000.3},
    {timestamp:1003,price:2000.4},
    {timestamp:1010,price:2000.5},
  ]);
});

test('both signed differences and positive backwards distances remain chronological',()=>{
  const expected=[
    {timestamp:1000,price:2000.2},
    {timestamp:1003,price:2000.3},
    {timestamp:1003,price:2000.4},
    {timestamp:1010,price:2000.5},
  ];
  for (const deltas of [[7,0,3],[-7,0,-3],[7,0,-3]]) {
    const input=[{timestamp:1010,tick:200050000},
      {timestamp:deltas[0],tick:-10000},
      {timestamp:deltas[1],tick:-10000},
      {timestamp:deltas[2],tick:-10000}];
    assert.deepEqual(normalizeHistoricalBidTicks(input,1000,1010),expected);
  }
});

test('real cTrader samples accumulate signed price deltas including zero',()=>{
  assert.deepEqual(normalizeHistoricalBidTicks([
    {timestamp:1010,tick:120015},
    {timestamp:-2,tick:1},
    {timestamp:-2,tick:-2},
    {timestamp:0,tick:0},
    {timestamp:-2,tick:3},
  ],1004,1010),[
    {timestamp:1004,price:1.20017},
    {timestamp:1006,price:1.20014},
    {timestamp:1006,price:1.20014},
    {timestamp:1008,price:1.20016},
    {timestamp:1010,price:1.20015},
  ]);
});

test('historical tick decoding rejects corrupt prices, time bounds and unsafe deltas',()=>{
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1010,tick:0}],0,1010));
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1010,tick:1},{timestamp:-1,tick:-2}],0,1010));
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1010,tick:Number.MAX_SAFE_INTEGER},{timestamp:-1,tick:1}],0,1010));
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1010,tick:200000000},{timestamp:'x',tick:200100000}],0,1010));
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1011,tick:200000000}],0,1010));
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1010,tick:200000000},{timestamp:-11,tick:200100000}],1000,1010));
  assert.throws(()=>normalizeHistoricalBidTicks([{timestamp:1010,tick:200000000},{timestamp:Number.MAX_SAFE_INTEGER+1,tick:200100000}],1000,1010));
});

test('tick requests use broker read-only historical message 2145 with bid type',async()=>{
  const requests=[];
  class FakeSocket extends EventEmitter {
    constructor(){super();this.readyState=0;queueMicrotask(()=>{this.readyState=1;this.emit('open');});}
    send(data,callback=()=>{}){
      const packet=JSON.parse(data);requests.push(packet);
      callback();
      const responseType={2100:2101,2102:2103,2145:2146}[packet.payloadType];
      const payload=packet.payloadType===2102?{ctidTraderAccountId:packet.payload.ctidTraderAccountId}
        :packet.payloadType===2145?{ctidTraderAccountId:12345,hasMore:false,
          tickData:[{timestamp:1001,tick:200000000},{timestamp:-1,tick:-100000}]}:{};
      queueMicrotask(()=>this.emit('message',Buffer.from(JSON.stringify({
        clientMsgId:packet.clientMsgId,payloadType:responseType,payload}))));
    }
    close(){this.readyState=3;this.emit('close');}
  }
  const socket=new FakeSocket();
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const page=await gateway.channel(false).historicalBidTicks(12345,'read-only',987,1000,1001);
    assert.deepEqual(page.ticks.map(t=>t.timestamp),[1000,1001]);
    assert.deepEqual(page.ticks.map(t=>t.price),[1999,2000]);
    assert.equal(page.hasMore,false);
    const packet=requests.find(x=>x.payloadType===2145);
    assert.deepEqual(packet.payload,{ctidTraderAccountId:12345,symbolId:987,type:1,
      fromTimestamp:1000,toTimestamp:1001});
    await assert.rejects(gateway.channel(false).historicalBidTicks(12345,'read-only',987,0,604800001),/invalid_tick_window/);
  } finally {socket.close();}
});

test('broker full symbol metadata is account-authenticated and never guessed from light symbols',async()=>{
  const requests=[];
  class SymbolSocket extends EventEmitter {
    constructor(){super();this.readyState=0;queueMicrotask(()=>{this.readyState=1;this.emit('open');});}
    send(data,callback=()=>{}){
      const packet=JSON.parse(data);requests.push(packet);
      callback();
      const responseType={2100:2101,2102:2103,2116:2117}[packet.payloadType];
      const payload=packet.payloadType===2102?{ctidTraderAccountId:12345}
        :packet.payloadType===2116?{ctidTraderAccountId:12345,
          symbol:[{symbolId:987,digits:3,pipPosition:2}]}:{};
      queueMicrotask(()=>this.emit('message',Buffer.from(JSON.stringify({
        clientMsgId:packet.clientMsgId,payloadType:responseType,payload}))));
    }
    close(){this.readyState=3;this.emit('close');}
  }
  const socket=new SymbolSocket();
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const result=await gateway.channel(false).symbolDetails(12345,'read-only',987);
    assert.deepEqual(result,{symbolId:'987',digits:3,pipPosition:2});
    const packet=requests.find(x=>x.payloadType===2116);
    assert.deepEqual(packet.payload,{ctidTraderAccountId:12345,symbolId:[987]});
    await assert.rejects(gateway.channel(false).symbolDetails(12345,'read-only',0),/invalid_symbol_id/);
  } finally {socket.close();}
});

test('truncated broker tick page is only a density marker, never a partial candle input',async()=>{
  class TruncatedSocket extends EventEmitter {
    constructor(){super();this.readyState=0;queueMicrotask(()=>{this.readyState=1;this.emit('open');});}
    send(data,callback=()=>{}){
      const packet=JSON.parse(data);callback();
      const responseType={2100:2101,2102:2103,2145:2146}[packet.payloadType];
      const payload=packet.payloadType===2102?{ctidTraderAccountId:12345}
        :packet.payloadType===2145?{ctidTraderAccountId:12345,hasMore:true,
          tickData:[{timestamp:1010,tick:200000000},{timestamp:0,tick:100},
            {timestamp:0,tick:200}]}:{};
      queueMicrotask(()=>this.emit('message',Buffer.from(JSON.stringify({
        clientMsgId:packet.clientMsgId,payloadType:responseType,payload}))));
    }
    close(){this.readyState=3;this.emit('close');}
  }
  const socket=new TruncatedSocket();
  const gateway=new CTraderGateway('id','secret',{socketFactory:()=>socket});
  try {
    const page=await gateway.channel(false).historicalBidTicks(12345,'read-only',987,1000,1010);
    assert.deepEqual(page,{ticks:[],hasMore:true});
  } finally {socket.close();}
});
