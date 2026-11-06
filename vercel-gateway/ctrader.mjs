// Dedicated, read-only cTrader Open API JSON transport; never sends trade/order payload types.
import WebSocket from 'ws';
import { randomUUID } from 'node:crypto';
import { hash as tokenHash } from './session.mjs';

const REQUEST_RESPONSE = new Map([[2100,2101],[2149,2150],[2102,2103],[2114,2115],[2137,2138],[2145,2146],[2127,2128],[2129,2130]]);
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
/**
 * cTrader stores the newest tick's absolute millisecond time, then signed
 * differences relative to the immediately preceding (newer) tick. Since the
 * broker returns newest first, those subsequent deltas are negative or zero.
 * Do not turn negative deltas into positive distances: doing so rejects valid
 * broker history and leaves the Range chart blank.
 */
export function normalizeHistoricalBidTicks(raw, from, to) {
  if (!Array.isArray(raw)) throw Error('invalid_tick_response');
  let previous = null;
  const descending = raw.map((entry, index) => {
    const delta = Number(entry.timestamp);
    const rawPrice = Number(entry.tick);
    if (!Number.isSafeInteger(delta) || (index === 0 ? delta < 0 : delta > 0) ||
        !Number.isSafeInteger(rawPrice) || rawPrice <= 0) throw Error('invalid_tick_data');
    const timestamp = index === 0 ? delta : previous + delta;
    if (!Number.isSafeInteger(timestamp) || timestamp < from || timestamp > to ||
        (previous !== null && timestamp > previous)) throw Error('tick_timestamp_out_of_range');
    previous = timestamp;
    return {timestamp, price:rawPrice / 100000};
  });
  // Preserve broker order for multiple price changes at the same millisecond.
  return descending.reverse();
}
class Channel {
  constructor(mode, id, secret, socketFactory=(url,options)=>new WebSocket(url,options)) {
    this.mode=mode;
    this.id=id;
    this.secret=secret;
    this.socketFactory=socketFactory;
    this.socket=null;
    this.pending=new Map();
    this.listeners=new Map();
    this.subscribing=new Map();
    this.authorized=new Set();
    this.authorizing=new Map();
    this.connecting=null;
    this.heartbeat=null;
    this.historyQueue=Promise.resolve();
    this.nextHistoryAt=0;
  }
  async connect() {
    // An OPEN socket is not yet an authenticated cTrader application. All
    // concurrent callers must await the app-auth response (2101) first.
    if (this.connecting) return this.connecting;
    if (this.socket?.readyState === WebSocket.OPEN) return;
    this.connecting=(async()=>{
      const socket = await new Promise((resolve,reject)=>{
        const ws = this.socketFactory(HOSTS[this.mode],{handshakeTimeout:10000,maxPayload:4*1024*1024});
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
        this.authorizing.clear();
        this.subscribing.clear();
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
    // Chart, Market and Replay can request the same account concurrently.
    // One acknowledged account-auth message is sufficient for that token.
    const inflight=this.authorizing.get(key);
    if(inflight)return inflight;
    const job=(async()=>{
      const socket=this.socket;
      try {
        const response=await this.send(2102,{ctidTraderAccountId:accountId,accessToken});
        if(String(response.ctidTraderAccountId)!==String(accountId))throw new Error('Account mismatch');
      } catch(error) {
        // HTTP and WS callers already verify this exact token's read-only account grant.
        // The broker can retain account authorization on the socket across token refreshes.
        if(error.operation!==2102 || error.brokerCode!=='ALREADY_LOGGED_IN')throw error;
      }
      if(this.socket!==socket || socket.readyState!==WebSocket.OPEN)
        throw new Error('cTrader connection closed');
      this.authorized.add(key);
    })();
    this.authorizing.set(key,job);
    try {await job;} finally {if(this.authorizing.get(key)===job)this.authorizing.delete(key);}
  }
  async symbols(accountId,accessToken) {
    await this.account(accountId,accessToken);
    return (await this.send(2114,{ctidTraderAccountId:accountId,includeArchivedSymbols:false})).symbol||[];
  }
  async history(accountId,accessToken,symbolId,period,from,to,count) {
    await this.account(accountId,accessToken);
    const result=await this.queueHistory(2137,{ctidTraderAccountId:accountId,symbolId,period,
      fromTimestamp:from,toTimestamp:to,count});
    return {candles:(result.trendbar||[]).map(normalizeBar).sort((a,b)=>a.timestamp-b.timestamp),hasMore:result.hasMore===true};
  }
  // Both trend bars and tick history share the broker's 5 historical calls/s limit.
  async queueHistory(type,payload) {
    const job=this.historyQueue.then(async()=>{
      const wait=Math.max(0,this.nextHistoryAt-Date.now());
      if(wait) await new Promise(resolve=>setTimeout(resolve,wait));
      this.nextHistoryAt=Date.now()+250;
      return this.send(type,payload);
    });
    this.historyQueue=job.then(()=>undefined,()=>undefined);
    return job;
  }
  async historicalBidTicks(accountId,accessToken,symbolId,from,to) {
    if (!Number.isSafeInteger(from) || !Number.isSafeInteger(to) || from < 0 ||
        to < from || to-from > 604800000) throw Error('invalid_tick_window');
    await this.account(accountId,accessToken);
    const result=await this.queueHistory(2145,{ctidTraderAccountId:accountId,
      symbolId,type:1,fromTimestamp:from,toTimestamp:to});
    if (String(result.ctidTraderAccountId) !== String(accountId)) throw Error('tick_account_mismatch');
    const ticks=normalizeHistoricalBidTicks(result.tickData||[],from,to);
    // A full millisecond group at the pagination edge cannot be resumed safely
    // without a cursor. Fail explicitly rather than silently dropping quotes.
    if (result.hasMore===true && ticks.length>1 && ticks[0].timestamp===ticks[1].timestamp)
      throw Error('ambiguous_tick_pagination_boundary');
    if (result.hasMore===true && !ticks.length) throw Error('empty_tick_page_with_more');
    return {ticks,hasMore:result.hasMore===true};
  }
  async subscribe(accountId,accessToken,symbolId,cb) {
    await this.account(accountId,accessToken);
    const key=`${accountId}:${symbolId}`;
    let listeners=this.listeners.get(key);
    if(!listeners){
      listeners=new Set();
      this.listeners.set(key,listeners);
      // All callers share the broker's acknowledgement. If the first subscribe
      // is rejected, no second caller may silently report success.
      const awaiting=this.send(2127,{ctidTraderAccountId:accountId,symbolId:[symbolId],subscribeToSpotTimestamp:true})
        .catch(error=>{
          if(this.listeners.get(key)===listeners)this.listeners.delete(key);
          throw error;
        }).finally(()=>{
          if(this.subscribing.get(key)===awaiting)this.subscribing.delete(key);
        });
      this.subscribing.set(key,awaiting);
    }
    const awaiting=this.subscribing.get(key);
    listeners.add(cb);
    try {
      if(awaiting)await awaiting;
    } catch(e){listeners.delete(cb);if(!listeners.size&&this.listeners.get(key)===listeners)this.listeners.delete(key);throw e;}
    return ()=>{
      if(this.listeners.get(key)!==listeners)return;
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
  constructor(clientId,clientSecret,{socketFactory}={}) {
    this.channels={live:new Channel('live',clientId,clientSecret,socketFactory),
      demo:new Channel('demo',clientId,clientSecret,socketFactory)};
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
