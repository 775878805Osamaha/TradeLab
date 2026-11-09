// Dedicated, read-only cTrader Open API JSON transport; never sends trade/order payload types.
import WebSocket from 'ws';
import { randomUUID } from 'node:crypto';
import { hash as tokenHash } from './session.mjs';

const REQUEST_RESPONSE = new Map([[2100,2101],[2149,2150],[2102,2103],[2114,2115],[2116,2117],[2137,2138],[2145,2146],[2127,2128],[2129,2130]]);
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
  // Per cTrader Open API, OHLC deltas are positive offsets from LOW in
  // 1/100000 price units. Never repair a malformed broker bar with guessed
  // prices, missing timestamps, or a synthetic candle.
  if (!raw || raw.low == null || raw.utcTimestampInMinutes == null)
    throw Error('invalid_ctrader_trendbar');
  const tsMinutes = Number(raw.utcTimestampInMinutes);
  const rawLow = Number(raw.low);
  const deltaOpen = Number(raw.deltaOpen ?? 0);
  const deltaHigh = Number(raw.deltaHigh ?? 0);
  const deltaClose = Number(raw.deltaClose ?? 0);
  const volume = Number(raw.volume ?? 0);
  if (![tsMinutes,rawLow,deltaOpen,deltaHigh,deltaClose,volume]
    .every(Number.isSafeInteger) || tsMinutes <= 0 || rawLow <= 0 ||
    deltaOpen < 0 || deltaHigh < 0 || deltaClose < 0 || volume < 0 ||
    deltaOpen > deltaHigh || deltaClose > deltaHigh)
    throw Error('invalid_ctrader_trendbar');
  const timestamp=tsMinutes*60000;
  if (!Number.isSafeInteger(timestamp))
    throw Error('invalid_ctrader_trendbar');
  const low = rawLow/100000;
  const open = (rawLow+deltaOpen)/100000;
  const high = (rawLow+deltaHigh)/100000;
  const close = (rawLow+deltaClose)/100000;
  if (![low,open,high,close].every(Number.isFinite) ||
      low > open || low > close || high < open || high < close)
    throw Error('invalid_ctrader_trendbar');
  return {timestamp,open,high,low,close,volume};
}
/**
 * cTrader stores the newest tick's absolute millisecond time, then signed
 * differences relative to the immediately preceding (newer) tick. Some tick
 * payloads express the backwards distance as a signed negative difference,
 * while others encode a positive distance. Both represent a move backwards
 * from the newest tick; never treat either sign as a future quote. Validate
 * the resulting absolute time against the requested broker interval. Prices
 * are also delta encoded: the first price is absolute, subsequent ticks are
 * signed differences relative to the previous (newer) quote.
 */
export function normalizeHistoricalBidTicks(raw, from, to) {
  if (!Array.isArray(raw)) throw Error('invalid_tick_response');
  let previous = null;
  let previousPrice = null;
  const descending = raw.map((entry, index) => {
    if (entry?.timestamp == null) throw Error('invalid_tick_timestamp');
    if (entry?.tick == null) throw Error('invalid_tick_price');
    const delta = Number(entry.timestamp);
    const priceDelta = Number(entry.tick);
    if (!Number.isSafeInteger(delta) || (index === 0 && delta < 0))
      throw Error('invalid_tick_timestamp');
    if (!Number.isSafeInteger(priceDelta))
      throw Error('invalid_tick_price');
    const rawPrice = index === 0 ? priceDelta : previousPrice + priceDelta;
    if (!Number.isSafeInteger(rawPrice) || rawPrice <= 0)
      throw Error('invalid_tick_price');
    const timestamp = index === 0 ? delta : previous - Math.abs(delta);
    if (!Number.isSafeInteger(timestamp) || timestamp < from || timestamp > to ||
        (previous !== null && timestamp > previous)) throw Error('tick_timestamp_out_of_range');
    previous = timestamp;
    previousPrice = rawPrice;
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
  /** Full broker metadata is account-specific; the light symbol list has no digits. */
  async symbolDetails(accountId,accessToken,symbolId) {
    if (!Number.isSafeInteger(symbolId)||symbolId<=0) throw Error('invalid_symbol_id');
    await this.account(accountId,accessToken);
    const result=await this.send(2116,{ctidTraderAccountId:accountId,symbolId:[symbolId]});
    if(String(result.ctidTraderAccountId)!==String(accountId))throw Error('symbol_account_mismatch');
    const symbol=(result.symbol||[]).find(item=>String(item.symbolId)===String(symbolId));
    if(!symbol || !Number.isInteger(symbol.digits) || symbol.digits<0 || symbol.digits>10 ||
        !Number.isInteger(symbol.pipPosition) || symbol.pipPosition<0 || symbol.pipPosition>10)
      throw Error('invalid_symbol_metadata');
    return {symbolId:String(symbolId),digits:symbol.digits,pipPosition:symbol.pipPosition};
  }
  async history(accountId,accessToken,symbolId,period,from,to,count) {
    if(!Number.isSafeInteger(from) || !Number.isSafeInteger(to) ||
        from<0 || to<from || !Number.isInteger(count) || count<1 || count>1000)
      throw Error('invalid_trendbar_window');
    await this.account(accountId,accessToken);
    let requests=0;
    const load=async(fromMs,toMs,depth=0)=>{
      if(++requests>32)
        throw Error('ctrader_candle_history_unusable');
      let segment;
      try {
        segment=await this.trendbarSlice(
          accountId,symbolId,period,fromMs,toMs,count);
      } catch(error) {
        // Backend history boundaries depend on the selected timeframe.
        // Split only this specific broker rejection; never conceal auth,
        // symbol, account-provenance or OHLC integrity failures.
        if(error?.brokerCode!=='INCORRECT_BOUNDARIES' ||
           error?.operation!==2137)throw error;
        if(depth>=10 || toMs-fromMs<120000)
          throw Error('ctrader_candle_history_unusable');
        const mid=fromMs+Math.floor((toMs-fromMs)/2);
        // The Flutter chart requests pages newest-first. If the broker rejects
        // this broad interval, search its newest half before older history.
        // Never fetch an entire 89-day M1/M3 interval just to show the first
        // screen: doing so exhausts the per-request safety budget (HTTP 502).
        const newer=await load(mid+1,toMs,depth+1);
        if(newer.candles.length) {
          // The older half was not requested, so this is an incomplete page.
          // The next chart page uses the earliest returned candle as cursor.
          return {candles:newer.candles,hasMore:true};
        }
        return load(fromMs,mid,depth+1);
      }
      // A truncated response still contains authenticated, validated broker
      // OHLC. The hasMore flag marks it as a PAGE, not a complete interval.
      // Flutter pages backwards with an exclusive cursor and never treats a
      // partial page as complete Range tick history.
      return segment;
    };
    return load(from,to);
  }

  async trendbarSlice(accountId,symbolId,period,from,to,count) {
    const result=await this.queueHistory(2137,{ctidTraderAccountId:accountId,symbolId,period,
      fromTimestamp:from,toTimestamp:to,count});
    // Broker account ID is required by ProtoOAGetTrendbarsRes. A response
    // belonging to another account must never be labeled as this user's
    // XAUUSD chart, even when prices and symbol names look plausible.
    if (String(result.ctidTraderAccountId) !== String(accountId) ||
        (result.symbolId != null && String(result.symbolId) !== String(symbolId)) ||
        (result.period != null && Number(result.period) !== Number(period)) ||
        (result.trendbar != null && !Array.isArray(result.trendbar)))
      throw Error('ctrader_trendbar_provenance_mismatch');
    // Some cTrader installations honor "count from toTimestamp" before
    // applying fromTimestamp. An extra older closed bar is real broker data
    // but lies outside our requested chart window. Filter it, never
    // misclassify that valid response as an invalid HTTP request.
    const relevant=[];
    for(const raw of result.trendbar||[]) {
      // Inspect only the broker's UTC open time to identify out-of-range
      // overfetch. An unrelated old bar with malformed OHLC must not poison
      // the requested interval; a malformed timestamp is still fatal.
      const minute=Number(raw?.utcTimestampInMinutes);
      const timestamp=minute*60000;
      if(!Number.isSafeInteger(minute) || minute<=0 ||
         !Number.isSafeInteger(timestamp))
        throw Error('invalid_ctrader_trendbar_timestamps');
      if(timestamp<from || timestamp>to)continue;
      relevant.push(normalizeBar(raw));
    }
    const ordered=relevant.sort((a,b)=>a.timestamp-b.timestamp);
    const candles=[];
    for(const bar of ordered) {
      const previous=candles[candles.length-1];
      if(previous?.timestamp===bar.timestamp) {
        // Identical duplicate source records may be ignored safely, but
        // conflicting OHLC for a single broker candle is a hard error.
        if(previous.open!==bar.open || previous.high!==bar.high ||
           previous.low!==bar.low || previous.close!==bar.close ||
           previous.volume!==bar.volume)
          throw Error('invalid_ctrader_trendbar_timestamps');
        continue;
      }
      candles.push(bar);
    }
    return {candles,hasMore:result.hasMore===true};
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
    // cTrader does not guarantee that a capped page ends on a unique
    // millisecond. Returning a truncated list would tempt clients to advance
    // to oldest-1ms and permanently omit other quotes at that timestamp.
    // Send only the density marker; Android retries with narrower DISJOINT
    // time windows. This also avoids serializing useless megabytes of data.
    if(result.hasMore===true)return {ticks:[],hasMore:true};
    const ticks=normalizeHistoricalBidTicks(result.tickData||[],from,to);
    return {ticks,hasMore:false};
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
