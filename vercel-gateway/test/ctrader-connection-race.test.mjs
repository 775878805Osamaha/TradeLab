import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { CTraderGateway } from '../ctrader.mjs';

/** In-memory cTrader proxy that refuses account-list requests before app auth. */
class FakeBrokerSocket extends EventEmitter {
  constructor({rejectSubscribe=false}={}) {
    super();
    this.readyState=0;
    this.appAuthed=false;
    this.packets=[];
    this.rejectSubscribe=rejectSubscribe;
    queueMicrotask(()=>{this.readyState=1;this.emit('open');});
  }
  send(data,cb=()=>{}) {
    const packet=JSON.parse(data);
    this.packets.push(packet.payloadType);
    cb();
    const respond=(type,payload={})=>this.emit('message',Buffer.from(JSON.stringify({
      clientMsgId:packet.clientMsgId,payloadType:type,payload
    })));
    if(packet.payloadType===2100) {
      setTimeout(()=>{this.appAuthed=true;respond(2101);},40);
    } else if(packet.payloadType===2149) {
      queueMicrotask(()=>{
        if(!this.appAuthed)respond(2142,{errorCode:'CH_CLIENT_NOT_AUTHENTICATED'});
        else respond(2150,{permissionScope:0,ctidTraderAccount:[]});
      });
    } else if(packet.payloadType===2102) {
      setTimeout(()=>respond(2103,{ctidTraderAccountId:packet.payload.ctidTraderAccountId}),15);
    } else if(packet.payloadType===2127) {
      setTimeout(()=>this.rejectSubscribe
        ?respond(2142,{errorCode:'SUBSCRIPTION_REJECTED'})
        :respond(2128),25);
    } else if(packet.payloadType===2129) {
      queueMicrotask(()=>respond(2130));
    }
  }
  close() { if(this.readyState!==3){this.readyState=3;this.emit('close');} }
}

test('parallel requests await application auth, even after the WebSocket opens',async()=>{
  const sockets=[];
  const gateway=new CTraderGateway('test-client','test-secret',{
    socketFactory:()=>{
      const socket=new FakeBrokerSocket();sockets.push(socket);return socket;
    }
  });
  try {
    const channel=gateway.channels.demo;
    const first=channel.request(2149,{accessToken:'token-test-1'});
    // The socket is OPEN, but the broker has not acknowledged app auth yet.
    await new Promise(resolve=>setTimeout(resolve,10));
    const second=channel.request(2149,{accessToken:'token-test-2'});
    const results=await Promise.all([first,second]);
    assert.equal(results.length,2);
    assert.deepEqual(sockets[0].packets.slice(0,3),[2100,2149,2149]);
  } finally {sockets.forEach(s=>s.close());}
});

test('parallel symbol and quote requests share one in-flight account authorization',async()=>{
  const sockets=[];
  const gateway=new CTraderGateway('test-client','test-secret',{
    socketFactory:()=>{const socket=new FakeBrokerSocket();sockets.push(socket);return socket;}
  });
  try {
    const channel=gateway.channels.demo;
    await Promise.all([
      channel.account(12345,'read-only-test-token'),
      channel.account(12345,'read-only-test-token')
    ]);
    assert.equal(sockets[0].packets.filter(type=>type===2102).length,1);
  } finally {sockets.forEach(s=>s.close());}
});

test('parallel spot listeners both fail when cTrader rejects the initial subscription',async()=>{
  const sockets=[];
  const gateway=new CTraderGateway('test-client','test-secret',{
    socketFactory:()=>{
      const socket=new FakeBrokerSocket({rejectSubscribe:true});
      sockets.push(socket);return socket;
    }
  });
  try {
    const channel=gateway.channels.demo;
    const attempts=await Promise.allSettled([
      channel.subscribe(12345,'read-only-test-token',987,()=>{}),
      channel.subscribe(12345,'read-only-test-token',987,()=>{})
    ]);
    assert.deepEqual(attempts.map(a=>a.status),['rejected','rejected']);
    assert.equal(channel.listeners.size,0);
    assert.equal(sockets[0].packets.filter(type=>type===2127).length,1);
    // A subsequent attempt can recover without a ghost listener or old promise.
    sockets[0].rejectSubscribe=false;
    const stop=await channel.subscribe(12345,'read-only-test-token',987,()=>{});
    assert.equal(sockets[0].packets.filter(type=>type===2127).length,2);
    stop();
  } finally {sockets.forEach(s=>s.close());}
});

test('parallel spot listeners both wait for a single accepted subscription',async()=>{
  const sockets=[];
  const gateway=new CTraderGateway('test-client','test-secret',{
    socketFactory:()=>{const socket=new FakeBrokerSocket();sockets.push(socket);return socket;}
  });
  try {
    const channel=gateway.channels.demo;
    const pending=[
      channel.subscribe(12345,'read-only-test-token',987,()=>{}),
      channel.subscribe(12345,'read-only-test-token',987,()=>{})
    ];
    const unsubscribers=await Promise.all(pending);
    assert.equal(sockets[0].packets.filter(type=>type===2127).length,1);
    unsubscribers.forEach(stop=>stop());
    assert.equal(sockets[0].packets.filter(type=>type===2129).length,1);
  } finally {sockets.forEach(s=>s.close());}
});
