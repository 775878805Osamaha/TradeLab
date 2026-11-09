import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { randomToken, hash, constantTimeMatch, sealedCodec } from '../session.mjs';
import { CTraderGateway, PERIODS } from '../ctrader.mjs';
import { encodeTickResponse } from '../tick-response.mjs';
import { authPage } from '../auth-page.mjs';

// Vercel's single free-tier web service. It keeps no database of user credentials:
// broker tokens are encrypted with a SERVER-ONLY key and retained in the Android Keystore.
const upstream = new CTraderGateway(process.env.CTRADER_CLIENT_ID, process.env.CTRADER_CLIENT_SECRET);
const securityHeaders = {
  'Cache-Control':'no-store',
  'Referrer-Policy':'no-referrer',
  'X-Content-Type-Options':'nosniff',
  'X-Frame-Options':'DENY',
  'Access-Control-Allow-Origin':'null',
};
const validToken = v => typeof v==='string' && /^[A-Za-z0-9_-]{43}$/.test(v);
// OAuth remains disabled by default for safe, credential-free integration tests.
// Enable only after server encryption keys are securely rotated and smoke-tested.
const oauthEnabled = process.env.CTRADER_AUTH_ENABLED !== 'false' &&
  !!(process.env.CTRADER_CLIENT_ID && process.env.CTRADER_CLIENT_SECRET &&
    process.env.SESSION_ENCRYPTION_KEY);
function publicOrigin(req) {
  const configured = process.env.PUBLIC_BASE_URL ||
    (process.env.VERCEL_PROJECT_PRODUCTION_URL ? 'https://'+process.env.VERCEL_PROJECT_PRODUCTION_URL : null);
  const host = configured || 'https://'+(req.headers.host||'');
  const url = new URL(host);
  if(url.protocol!=='https:' || url.origin!==host || (url.port && url.port!=='443')) throw Error('invalid_origin');
  if(!configured && !url.hostname.endsWith('.vercel.app'))throw Error('untrusted_origin');
  return url.origin;
}
function getRuntime(req) {
  if(!process.env.CTRADER_CLIENT_ID||!process.env.CTRADER_CLIENT_SECRET||
      !process.env.SESSION_ENCRYPTION_KEY)throw Error('unconfigured_gateway');
  return { codec:sealedCodec(process.env.SESSION_ENCRYPTION_KEY, process.env.CTRADER_CLIENT_SECRET),
    base:publicOrigin(req) };
}
function route(req) {
  const u=new URL(req.url,'https://server.local');
  const p=u.searchParams.get('path');
  const path=p ? '/'+p.replace(/^\/+/, '') : u.pathname;
  return {url:u,path};
}
function reply(res,code,body,extra={}) {
  if(res.headersSent)return;
  res.writeHead(code,{...securityHeaders,'Content-Type':'application/json; charset=utf-8',...extra});
  res.end(JSON.stringify(body));
}
async function tickReply(req,res,body,extra={}) {
  if(res.headersSent)return;
  const {bytes,headers}=await encodeTickResponse(body,req.headers['accept-encoding']||'');
  if(res.headersSent)return;
  res.writeHead(200,{...securityHeaders,'Content-Type':'application/json; charset=utf-8',
    'Content-Length':bytes.length,...headers,...extra});
  res.end(bytes);
}
function redirect(res,url,extra={}) {
  res.writeHead(302,{...securityHeaders,Location:url,...extra});res.end();
}
function html(res,code,body,extra={}) {
  res.writeHead(code,{...securityHeaders,'Content-Type':'text/html; charset=utf-8',
    'Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",...extra});
  res.end(body);
}
function fail(res,code,reason){reply(res,code,{error:reason});}
function cookie(value,maxAge){
  return `ct_oauth=${value}; Max-Age=${maxAge}; Path=/auth/ctrader; HttpOnly; Secure; SameSite=Lax`;
}
function getCookie(req,name){
  return (req.headers.cookie||'').split(';').map(x=>x.trim())
    .find(x=>x.startsWith(name+'='))?.slice(name.length+1);
}
async function jsonBody(req){
  if(!req.headers['content-type']?.startsWith('application/json'))throw Error('invalid_content_type');
  let body='';
  for await(const chunk of req) {
    body+=chunk.toString('utf8');
    if(body.length>8192)throw Error('body_too_large');
  }
  return JSON.parse(body);
}
async function exchangeToken(args){
  const url=new URL('https://openapi.ctrader.com/apps/token');
  for(const [key,value] of Object.entries({...args,
    client_id:process.env.CTRADER_CLIENT_ID,
    client_secret:process.env.CTRADER_CLIENT_SECRET
  }))url.searchParams.set(key,String(value));
  // cTrader's documented OAuth token endpoint takes GET query parameters.
  // Never log the URL or reveal upstream errors, which could contain credentials.
  const result=await fetch(url.toString(),{headers:{Accept:'application/json'},
    signal:AbortSignal.timeout(12000),cache:'no-store'});
  if(!result.ok)throw Error('broker_exchange_failed');
  const data=await result.json();
  if(data.errorCode||!data.accessToken||!data.refreshToken||
     !Number.isFinite(Number(data.expiresIn)))throw Error('broker_exchange_failed');
  return {access:data.accessToken,refresh:data.refreshToken,
    until:Date.now()+Number(data.expiresIn)*1000};
}
function sealedSession(codec,data){
  return codec.seal({v:1,type:'session',scope:'accounts',issued:Date.now(),...data});
}
async function getSession(req,codec){
  const bearer=req.headers.authorization||'';
  if(!bearer.startsWith('Bearer '))throw Error('not_authenticated');
  const session=codec.open(bearer.substring(7));
  if(session.v!==1 || session.type!=='session' || session.scope!=='accounts' ||
     typeof session.access!=='string'||typeof session.refresh!=='string'||
     !Number.isFinite(Number(session.until)) || 
     !Number.isFinite(Number(session.issued))||
     session.issued>Date.now()+30000 || session.issued<Date.now()-90*86400000)
     throw Error('invalid_session');
  if(session.until>Date.now()+5*60000)return {access:session.access,tokenUpdate:null};
  const refreshed=await exchangeToken({grant_type:'refresh_token',refresh_token:session.refresh});
  return {access:refreshed.access,tokenUpdate:sealedSession(codec,refreshed)};
}
function requireAccountId(raw){
  if(!/^[1-9][0-9]*$/.test(raw||''))throw Error('invalid_account_id');
  const id=Number(raw);
  if(!Number.isSafeInteger(id))throw Error('invalid_account_id');
  return id;
}
async function accountAccess(session,url){
  const id=requireAccountId(url.searchParams.get('accountId'));
  const allowed=await upstream.accounts(session.access);
  const entry=allowed.find(x=>x.accountId===String(id));
  if(!entry)throw Error('account_not_authorized');
  return {id,entry};
}
function intArg(url,key,min,max){
  const str=url.searchParams.get(key);
  if(!/^[0-9]+$/.test(str||''))throw Error('invalid_'+key);
  const n=Number(str);
  if(!Number.isSafeInteger(n)||n<min||n>max)throw Error('invalid_'+key);
  return n;
}
async function getSpot(channel,id,access,symbol){
  let unsub=()=>{}, finished=false;
  try {
    return await new Promise(async(resolve,reject)=>{
      const timer=setTimeout(()=>{finished=true;reject(Error('quote_timeout'));},16000);
      let bid=null,ask=null,lastTimestamp=null;
      const callback=p=>{
        if(finished)return;
        if(p.bid!=null)bid=Number(p.bid);
        if(p.ask!=null)ask=Number(p.ask);
        if(p.timestamp!=null)lastTimestamp=Number(p.timestamp);
        // Never substitute the server's clock for a missing broker timestamp.
        // A single-sided spot event is insufficient to price a paper trade.
        if(Number.isFinite(bid)&&Number.isFinite(ask)&&bid>0&&ask>=bid&&
          Number.isSafeInteger(lastTimestamp)&&lastTimestamp>0){
          finished=true;clearTimeout(timer);
          resolve({bid,ask,timestamp:lastTimestamp});
        }
      };
      try {unsub=await channel.subscribe(id,access,symbol,callback);}
      catch(e){clearTimeout(timer);finished=true;reject(e);}
    });
  } finally {unsub();}
}
async function handler(req,res){
  const {path,url}=route(req);
  if(req.method==='GET' && path==='/healthz')return reply(res,200,{
    status:'ok',service:'TradeLab cTrader OAuth gateway',
    flutterOAuthSupported:true,
    transportRevision:'account-already-logged-in-2026-11-04',
    brokerErrorDetails:true,
    configured:!!(process.env.CTRADER_CLIENT_ID&&process.env.CTRADER_CLIENT_SECRET&&process.env.SESSION_ENCRYPTION_KEY),
    authEnabled:oauthEnabled
  });
  if(!oauthEnabled)return fail(res,503,'authentication_paused_for_security');
  const {codec,base}=getRuntime(req);
  const callback=base+'/auth/ctrader/callback';
  if(req.method==='GET' && path==='/auth/ctrader/start'){
    const challenge=url.searchParams.get('challenge');
    if(!validToken(challenge))return fail(res,400,'invalid_challenge');
    const client=url.searchParams.get('client')||'native';
    if(!['native','flutter'].includes(client))return fail(res,400,'invalid_client');
    const flow=codec.seal({type:'flow',v:1,challenge,client,nonce:randomUUID(),
      expires:Date.now()+10*60000});
    const target=new URL('https://id.ctrader.com/my/settings/openapi/grantingaccess/');
    for(const [k,v] of Object.entries({client_id:process.env.CTRADER_CLIENT_ID,
        redirect_uri:callback,scope:'accounts',product:'web'}))target.searchParams.set(k,v);
    return redirect(res,target.toString(),{'Set-Cookie':cookie(flow,600)});
  }
  if(req.method==='GET'&&path==='/auth/ctrader/callback') {
    const clear={'Set-Cookie':cookie('',0)};
    let flow;
    try {flow=codec.open(getCookie(req,'ct_oauth'));}
    catch {return html(res,400,'<p>انتهت جلسة تسجيل الدخول. ابدأ من TradeLab مرة أخرى.</p>',clear);}
    if(flow.type!=='flow'||flow.v!==1||!validToken(flow.challenge)||
       flow.expires<Date.now()||flow.expires>Date.now()+10*60000)
       return html(res,400,'<p>جلسة تسجيل الدخول غير صالحة.</p>',clear);
    const code=url.searchParams.get('code');
    if(url.searchParams.has('error')||!code||code.length>2048)
       return html(res,400,'<p>لم يتم منح إذن cTrader.</p>',clear);
    let tokens;
    try {tokens=await exchangeToken({grant_type:'authorization_code',code,redirect_uri:callback});}
    catch {return html(res,502,'<p>فشل تأكيد cTrader. افتح التطبيق وحاول مجددًا.</p>',clear);}
    // Short-lived, tamper-proof handoff. Only the Android device which knows the
    // initial verifier can redeem it. Unlike a DB ticket it cannot be revoked
    // on first use, but expires in two minutes and carries encrypted content.
    const ticket=codec.seal({v:1,type:'handoff',challenge:flow.challenge,
      expires:Date.now()+120000,...tokens});
    const page=authPage(ticket,flow.client==='flutter'?'flutter':'native');
    return html(res,200,page.body,{...clear,'Content-Security-Policy':
      `default-src 'none'; script-src 'nonce-${page.nonce}'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'`});
  }
  if(req.method==='POST'&&path==='/auth/ctrader/redeem'){
    const body=await jsonBody(req);
    const token=body.ticket, verifier=body.verifier;
    if(typeof token!=='string'||token.length>6144||!validToken(verifier))
      return fail(res,400,'invalid_handoff');
    let handoff;
    try {handoff=codec.open(token);}
    catch {return fail(res,401,'invalid_handoff');}
    if(handoff.type!=='handoff'||handoff.v!==1||handoff.expires<Date.now()||
       handoff.expires>Date.now()+120000||!constantTimeMatch(handoff.challenge,hash(verifier)))
      return fail(res,401,'expired_or_invalid_handoff');
    return reply(res,200,{sessionToken:sealedSession(codec,{
      access:handoff.access,refresh:handoff.refresh,until:handoff.until}),permission:'read_only'});
  }

  if(req.method==='GET'&&path.startsWith('/v1/')){
    const session=await getSession(req,codec);
    const sessionHeader=session.tokenUpdate?{'X-TradeLab-Session':session.tokenUpdate}:{};
    if(path==='/v1/session')return reply(res,200,{linked:true,scope:'accounts'},sessionHeader);
    if(path==='/v1/accounts')return reply(res,200,{accounts:await stage('accounts',()=>upstream.accounts(session.access))},sessionHeader);
    if(path==='/v1/symbols'){
      const {id,entry}=await stage('symbols',()=>accountAccess(session,url));
      const symbols=await stage('symbols',()=>upstream.channel(entry.isLive).symbols(id,session.access));
      return reply(res,200,{accountId:String(id),symbols},sessionHeader);
    }
    if(path==='/v1/symbol-detail'){
      const {id,entry}=await stage('symbols',()=>accountAccess(session,url));
      const symbolId=intArg(url,'symbolId',1,Number.MAX_SAFE_INTEGER);
      const detail=await stage('symbols',()=>upstream.channel(entry.isLive)
        .symbolDetails(id,session.access,symbolId));
      return reply(res,200,{accountId:String(id),source:'ctrader',...detail},sessionHeader);
    }
    if(path==='/v1/candles'){
      const {id,entry}=await stage('candles',()=>accountAccess(session,url));
      const symbolId=intArg(url,'symbolId',1,Number.MAX_SAFE_INTEGER);
      const periodName=url.searchParams.get('period');
      const period=PERIODS[periodName];
      if(!period)return fail(res,400,'unsupported_period');
      const from=intArg(url,'from',0,2147483646000),
            to=intArg(url,'to',from,2147483646000),
            count=intArg(url,'count',1,1000);
      if(to-from>90*86400000)return fail(res,400,'date_window_too_wide');
      const data=await stage('candles',()=>upstream.channel(entry.isLive).history(id,session.access,symbolId,period,from,to,count));
      // Carry the authenticated broker account identity through to Flutter.
      // A source label alone cannot prove that the selected XAUUSD feed
      // belongs to the currently selected cTrader broker account.
      return reply(res,200,{accountId:String(id),symbolId:String(symbolId),
        period:periodName,source:'ctrader',...data},sessionHeader);
    }
    if(path==='/v1/ticks'){
      const {id,entry}=await stage('ticks',()=>accountAccess(session,url));
      const symbolId=intArg(url,'symbolId',1,Number.MAX_SAFE_INTEGER);
      const from=intArg(url,'from',0,2147483646000);
      const to=intArg(url,'to',from,2147483646000);
      if(to-from>604800000)return fail(res,400,'tick_window_exceeds_one_week');
      const data=await stage('ticks',()=>upstream.channel(entry.isLive)
        .historicalBidTicks(id,session.access,symbolId,from,to));
      return tickReply(req,res,{symbolId:String(symbolId),source:'ctrader',quoteType:'bid',...data},sessionHeader);
    }
    if(path==='/v1/spot'){
      const {id,entry}=await stage('spot',()=>accountAccess(session,url));
      const symbolId=intArg(url,'symbolId',1,Number.MAX_SAFE_INTEGER);
      const quote=await stage('spot',()=>getSpot(upstream.channel(entry.isLive),id,session.access,symbolId));
      return reply(res,200,{symbolId:String(symbolId),timestamp:Number(quote.timestamp),
        source:'ctrader',...(quote.bid==null?{}:{bid:Number(quote.bid)/1e5}),
        ...(quote.ask==null?{}:{ask:Number(quote.ask)/1e5})},sessionHeader);
    }
  }
  if(req.method==='POST'&&path==='/v1/logout')
    return reply(res,200,{linked:false,clientOnly:true,
      note:'Clear the Android session and revoke app access in cTrader portal if needed.'});
  return fail(res,404,'not_found');
}
async function stage(name,fn){
  try{return await fn();}catch(error){error.stage=name;throw error;}
}
function safeDiagnostic(error){
  const category=String(error?.message||'');
  return {
    stage:['accounts','symbols','candles','ticks','spot'].includes(error?.stage)?error.stage:'other',
    category:/^(ctrader_[a-z_]+|cTrader connection closed|not_authenticated|invalid_session|account_not_authorized|broker_exchange_failed|invalid_tick_data|invalid_tick_timestamp|invalid_tick_price|tick_timestamp_out_of_range|tick_account_mismatch|ambiguous_tick_pagination_boundary|empty_tick_page_with_more|symbol_account_mismatch|invalid_symbol_metadata)$/.test(category)
      ?category:'unclassified',
    brokerCode:/^[A-Z0-9_]{1,64}$/.test(error?.brokerCode||'')?error.brokerCode:undefined,
    operation:Number.isInteger(error?.operation)?error.operation:undefined
  };
}
// Public protocol enums only. Never forward arbitrary upstream text.
const publicBrokerCodes=new Set([
  'OA_AUTH_TOKEN_EXPIRED','ACCOUNT_NOT_AUTHORIZED','RET_NO_SUCH_LOGIN',
  'ALREADY_LOGGED_IN','INCORRECT_BOUNDARIES','RET_ACCOUNT_DISABLED',
  'CONNECTIONS_LIMIT_EXCEEDED','CH_CLIENT_AUTH_FAILURE','CH_CLIENT_NOT_AUTHENTICATED',
  'CH_CLIENT_ALREADY_AUTHENTICATED','CH_ACCESS_TOKEN_INVALID','CH_SERVER_NOT_REACHABLE',
  'CH_CTID_TRADER_ACCOUNT_NOT_FOUND','CH_OA_CLIENT_NOT_FOUND','REQUEST_FREQUENCY_EXCEEDED',
  'SERVER_IS_UNDER_MAINTENANCE','CHANNEL_IS_BLOCKED','ALREADY_SUBSCRIBED',
  'SYMBOL_NOT_FOUND','UNKNOWN_SYMBOL',
]);
export function brokerRejection(error) {
  const {stage,brokerCode,operation}=safeDiagnostic(error);
  return {
    error:'ctrader_broker_rejected_request',
    stage,
    brokerCode:publicBrokerCodes.has(brokerCode)?brokerCode:undefined,
    operation:[2100,2149,2102,2114,2116,2137,2145,2127].includes(operation)?operation:undefined,
  };
}
const server=createServer((req,res)=>{
  Promise.resolve(handler(req,res)).catch(error=>{
    // No tokens, account IDs, request URLs or upstream error descriptions.
    console.error('tradelab_ctrader_gateway',JSON.stringify(safeDiagnostic(error)));
    // Never send upstream URLs, tokens, stack traces, or encrypted credentials to clients.
    if(res.headersSent){res.end();return;}
    if(error.message==='unconfigured_gateway')return fail(res,503,'gateway_not_configured');
    if(error.message==='not_authenticated'||error.message==='invalid_session')
      return fail(res,401,'session_expired');
    if(['invalid_tick_data','invalid_tick_timestamp','invalid_tick_price','tick_timestamp_out_of_range','tick_account_mismatch',
      'ambiguous_tick_pagination_boundary','empty_tick_page_with_more'].includes(error.message))
      return fail(res,502,'ctrader_tick_history_unusable');
    if(error.message.startsWith('invalid_')||error.message==='account_not_authorized')
      return fail(res,400,'invalid_request');
    if(error.message==='ctrader_view_only_required')return fail(res,403,'ctrader_view_only_required');
    // Public, bounded error categories: never disclose tokens, credentials or upstream URLs.
    if(error.message==='ctrader_socket_connection_failed' ||
       error.message==='cTrader connection closed')
      return fail(res,503,'ctrader_connection_failed');
    if(error.message==='ctrader_request_timeout' || error.message==='quote_timeout')
      return fail(res,503,'ctrader_response_timeout');
    if(error.message==='ctrader_read_request_rejected')
      return reply(res,503,brokerRejection(error));
    if(error.message==='broker_exchange_failed')
      return fail(res,503,'ctrader_token_exchange_failed');
    return fail(res,503,'ctrader_broker_unavailable');
  });
});
const wss=new WebSocketServer({noServer:true,maxPayload:8192});
server.on('upgrade',(req,socket,head)=>{
  if(!oauthEnabled)return socket.destroy();
  const {path}=route(req);
  if(path!=='/v1/stream')return socket.destroy();
  wss.handleUpgrade(req,socket,head,ws=>wss.emit('connection',ws,req));
});
wss.on('connection',(client,req)=>{
  let unsubscribe=null, liveSession=null, ready=false;
  const timeout=setTimeout(()=>client.close(1008,'Authentication timeout'),10000);
  client.on('message',async raw=>{
    if(ready)return;
    ready=true;
    clearTimeout(timeout);
    try {
      const {codec}=getRuntime(req);
      const payload=JSON.parse(raw.toString());
      if(payload.type!=='subscribe'||typeof payload.session!=='string'||
         typeof payload.accountId!=='string'||typeof payload.symbolId!=='number')
         throw Error('invalid_subscribe');
      const fakeReq={headers:{authorization:'Bearer '+payload.session}};
      liveSession=await getSession(fakeReq,codec);
      if(liveSession.tokenUpdate){
        client.send(JSON.stringify({type:'session',sessionToken:liveSession.tokenUpdate}));
      }
      const query=new URL('https://app.local/v1/stream');
      query.searchParams.set('accountId',payload.accountId);
      const {id,entry}=await accountAccess(liveSession,query);
      const symbolId=payload.symbolId;
      if(!Number.isSafeInteger(symbolId)||symbolId<=0)throw Error('invalid_symbol');
      unsubscribe=await upstream.channel(entry.isLive).subscribe(id,liveSession.access,symbolId,spot=>{
        if(client.readyState===1)
          client.send(JSON.stringify({type:'spot',symbolId:String(symbolId),
            source:'ctrader',timestamp:spot.timestamp==null?null:Number(spot.timestamp),
            ...(spot.bid==null?{}:{bid:Number(spot.bid)/1e5}),
            ...(spot.ask==null?{}:{ask:Number(spot.ask)/1e5})}));
      });
    }catch{client.close(1008,'Unable to authorize cTrader stream');}
  });
  client.on('close',()=>{clearTimeout(timeout);unsubscribe?.();});
  client.on('error',()=>{clearTimeout(timeout);unsubscribe?.();});
});
export default server;
