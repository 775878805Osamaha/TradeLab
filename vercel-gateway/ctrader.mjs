// Dedicated, read-only cTrader Open API JSON transport; never sends trade/order payload types.
import WebSocket from 'ws';
import { randomUUID } from 'node:crypto';
import { hash as tokenHash } from './session.mjs';

const REQUEST_RESPONSE = new Map([[2100,2101],[2149,2150],[2102,2103],[2114,2115],[2137,2138],[2127,2128],[2129,2130]]);
const HOSTS = { demo: 'wss://demo.ctraderapi.com:5036', live: 'wss://live.ctraderapi.com:5036' };
export const PERIODS = Object.freeze({M1:1,M2:2,M3:3,M4:4,M5:5,M10:6,M15:7,M30:8,H1:9,H4:10,H12:11,D1:12,W1:13,MN1:14});
export function isReadOnlyScope(scope) {
  // cTrader marks scope optional in the response. Explicit trade scope is denied.
  return scope == null || scope === 0 || scope === '0' || scope === 'SCOPE_VIEW';
}
/**
 * Some brokers expose demo and live accounts through different hosts. Merge
 * only read-only grants; never select a trading-scope token or invent accounts.
 */
export function mergeReadOnlyAccountLists(results) {
  const accounts=new Map();
  for(const result of results) {
    if(!isReadOnlyScope(result.permissionScope))throw new Error('ctrader_view_only_required');
    for(const a of result.ctidTraderAccount||[]) {
      const accountId=String(a.ctidTraderAccountId||'');
      if(!/^[1-9][0-9]*$/.test(accountId))continue;
      const isLive=a.isLive===true;
      accounts.set(accountId,{
        accountId,isLive,broker:a.brokerTitleShort||'',
        login:a.traderLogin==null?null:String(a.traderLogin)
      });
    }
  }
  return [...accounts.values()];
}
export function normalizeBar(raw) {
  const low = Number(raw.low) / 100000;
  return {
    timestamp: Number(raw.utcTimestampInMinutes) * 60000,
    open: low + Number(raw.deltaOpen || 0) / 100000,
    high: low + Number(raw.deltaHigh || 0) / 100000,
    low,
    close: low + Number(raw.deltaClose || 0) / 100000,
    volume: Number(raw.volume || 0),
  };
}
class Channel {
  constructor(mode, id, secret) {
    this.mode=mode;
    this.id=id;
    this.secret=secret;
    this.socket=null;
    this.pending=new Map();
    this.listeners=new Map();
    this.authorized=new Set();
    this.connecting=null;
    this.heartbeat=null;
    this.historyQueue=Promise.resolve();
    this.nextHistoryAt=0;
  }
  async connect() {
    if (this.socket?.readyState === WebSocket.OPEN) return;
    if (this.connecting) return this.connecting;
    this.connecting=(async()=>{
      const socket = await new Promise((resolve,reject)=>{
        const ws = new WebSocket(HOSTS[this.mode],{handshakeTimeout:10000,maxPayload:4*1024*1024});
        ws.once('open',()=>resolve(ws));
        ws.once('error',()=>reject(new Error('ctrader_socket_connection_failed')));
      });
      this.socket=socket;
      socket.on('message', data=>{
        let packet;
        try { packet=JSON.parse(data.toString('utf8')); } catch { return; }
        if (packet.payloadType===2131) {
          const p=packet.payload||{};
          const key=`${p.ctidTraderAccountId}:${p.symbolId}`;
          for(const cb of (this.listeners.get(key)||[])) cb(p);
        }
        const request=this.pending.get(packet.clientMsgId);
        if (!request) return;
        if(packet.payloadType===2142 || packet.payloadType===50) {
          const failure=new Error('ctrader_read_request_rejected');
          // Only an enum-like code is safe for operational logs. Never log
          // the upstream description: it may contain broker account details.
          const brokerCode=String(packet.payload?.errorCode??'');
          failure.brokerCode=/^[A-Z0-9_]{1,64}$/.test(brokerCode)?brokerCode:'UNSPECIFIED';
          failure.operation=request.operation;
          request.reject(failure);
        } else if(packet.payloadType===request.expected) {
          request.resolve(packet.payload||{});
        } else return;
        clearTimeout(request.timer);
        this.pending.delete(packet.clientMsgId);
      });
      const fail=()=>{
        if(this.socket!==socket)return;
        this.socket=null;
        this.authorized.clear();
        if(this.heartbeat)clearInterval(this.heartbeat);
        this.heartbeat=null;
        for (const [key,p] of this.pending) {
          clearTimeout(p.timer);
          p.reject(new Error('cTrader connection closed'));
          this.pending.delete(key);
        }
        this.listeners.clear();
      };
      socket.on('close',fail);
      socket.on('error',fail);
      this.heartbeat=setInterval(()=>{
        if(socket.readyState===WebSocket.OPEN)
          socket.send(JSON.stringify({clientMsgId:randomUUID(),payloadType:51,payload:{}}));
      },9000);
      try {
        await this.send(2100,{clientId:this.id,clientSecret:this.secret});
      } catch(e) {
        socket.close();
        throw e;
      }
    })().finally(()=>{this.connecting=null;});
    return this.connecting;
  }
  async send(type,payload) {
    const expected=REQUEST_RESPONSE.get(type);
    if (!expected)throw new Error('Write or unsupported cTrader operation blocked');
    if(this.socket?.readyState!==WebSocket.OPEN)throw new Error('cTrader is offline');
    const clientMsgId=randomUUID();
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{
        this.pending.delete(clientMsgId);
        reject(new Error('ctrader_request_timeout'));
      },15000);
      this.pending.set(clientMsgId,{resolve,reject,timer,expected,operation:type});
      this.socket.send(JSON.stringify({clientMsgId,payloadType:type,payload}),err=>{
        if(err) {
          clearTimeout(timer);
          this.pending.delete(clientMsgId);
          reject(new Error('cTrader send failed'));
        }
      });
    });
  }
  async request(type,payload) {
    await this.connect();
    return this.send(type,payload);
  }
  async account(accountId,accessToken) {
    await this.connect();
    const key=`${accountId}:${tokenHash(accessToken)}`;
    if(this.authorized.has(key))return;
    const response=await this.send(2102,{ctidTraderAccountId:accountId,accessToken});
    if(String(response.ctidTraderAccountId)!==String(accountId))throw new Error('Account mismatch');
    this.authorized.add(key);
  }
  async symbols(accountId,accessToken) {
    await this.account(accountId,accessToken);
    return (await this.send(2114,{ctidTraderAccountId:accountId,includeArchivedSymbols:false})).symbol||[];
  }
  async history(accountId,accessToken,symbolId,period,from,to,count) {
    await this.account(accountId,accessToken);
    // cTrader permits only 5 historical requests/s per connection. Queue at <=4/s.
    const job=this.historyQueue.then(async()=>{
      const wait=Math.max(0,this.nextHistoryAt-Date.now());
      if(wait) await new Promise(resolve=>setTimeout(resolve,wait));
      this.nextHistoryAt=Date.now()+250;
      return this.send(2137,{ctidTraderAccountId:accountId,symbolId,period,
        fromTimestamp:from,toTimestamp:to,count});
    });
    this.historyQueue=job.then(()=>undefined,()=>undefined);
    const result=await job;
    return {candles:(result.trendbar||[]).map(normalizeBar).sort((a,b)=>a.timestamp-b.timestamp),hasMore:result.hasMore===true};
  }
  async subscribe(accountId,accessToken,symbolId,cb) {
    await this.account(accountId,accessToken);
    const key=`${accountId}:${symbolId}`;
    let listeners=this.listeners.get(key);
    if(!listeners){listeners=new Set();this.listeners.set(key,listeners);}
    const first=listeners.size===0;
    listeners.add(cb);
    try {
      if(first)await this.send(2127,{ctidTraderAccountId:accountId,symbolId:[symbolId],subscribeToSpotTimestamp:true});
    } catch(e){listeners.delete(cb);if(!listeners.size)this.listeners.delete(key);throw e;}
    return ()=>{
      listeners.delete(cb);
      if(!listeners.size) {
        this.listeners.delete(key);
        if(this.socket?.readyState===WebSocket.OPEN)
          this.send(2129,{ctidTraderAccountId:accountId,symbolId:[symbolId]}).catch(()=>{});
      }
    };
  }
}
export class CTraderGateway {
  constructor(clientId,clientSecret) {
    this.channels={live:new Channel('live',clientId,clientSecret),demo:new Channel('demo',clientId,clientSecret)};
    // Only read-only account metadata; scoped by hash of the OAuth token.
    // Avoid two Open API account-list requests on every history/spot page.
    this.accountCache=new Map();
  }
  async accounts(accessToken) {
    const key=tokenHash(accessToken);
    const cached=this.accountCache.get(key);
    if(cached && cached.until>Date.now())return cached.accounts;
    const results=await Promise.allSettled([
      this.channels.demo.request(2149,{accessToken}),
      this.channels.live.request(2149,{accessToken})
    ]);
    const fulfilled=results.filter(r=>r.status==='fulfilled').map(r=>r.value);
    if(!fulfilled.length)throw results[0].reason;
    const accounts=mergeReadOnlyAccountLists(fulfilled);
    if(this.accountCache.size>=256)this.accountCache.clear();
    this.accountCache.set(key,{accounts,until:Date.now()+20000});
    return accounts;
  }
  channel(isLive){return this.channels[isLive?'live':'demo'];}
}
