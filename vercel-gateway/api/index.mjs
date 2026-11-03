import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { randomToken, hash, constantTimeMatch, sealedCodec } from '../session.mjs';
import { CTraderGateway, PERIODS } from '../ctrader.mjs';

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
  let unsub=()=>{};
  try {
    return await new Promise(async(resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error('quote_timeout')),16000);
      const callback=p=>{clearTimeout(timer);resolve(p);};
      try {
        unsub=await channel.subscribe(id,access,symbol,callback);
      } catch(e){clearTimeout(timer);reject(e);}
    });
  } finally {unsub();}
}
function authPage(ticket) {
  const uri='tradelab://oauth/ctrader?ticket='+encodeURIComponent(ticket);
  const nonce=randomToken();
  const body=`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>TradeLab cTrader</title></head>
<body style="background:#071018;color:white;font-family:sans-serif;text-align:center;padding:42px 14px">
<h2>تم تفويض TradeLab للقراءة فقط</h2>
<p>اضغط لفتح تطبيق TradeLab وإكمال ربط حسابك.</p>
<a style="display:inline-block;padding:16px 24px;background:#00bda7;color:#001;border-radius:9px"
href="${uri}">فتح TradeLab</a>
<script nonce="${nonce}">location.replace(${JSON.stringify(uri)})</script></body></html>`;
  return {body,nonce};
}
async function handler(req,res){
  const {path,url}=route(req);
  if(req.method==='GET' && path==='/healthz')return reply(res,200,{
    status:'ok',service:'TradeLab cTrader OAuth gateway',
    configured:!!(process.env.CTRADER_CLIENT_ID&&process.env.CTRADER_CLIENT_SECRET&&process.env.SESSION_ENCRYPTION_KEY),
    authEnabled:oauthEnabled
  });
  if(!oauthEnabled)return fail(res,503,'authentication_paused_for_security');
  const {codec,base}=getRuntime(req);
  const callback=base+'/auth/ctrader/callback';
  if(req.method==='GET' && path==='/auth/ctrader/start'){
    const challenge=url.searchParams.get('challenge');
    if(!validToken(challenge))return fail(res,400,'invalid_challenge');
    const flow=codec.seal({type:'flow',v:1,challenge,nonce:randomUUID(),
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
    const page=authPage(ticket);
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
    if(path==='/v1/accounts')return reply(res,200,{accounts:await upstream.accounts(session.access)},sessionHeader);
    if(path==='/v1/symbols'){
      const {id,entry}=await accountAccess(session,url);
      const symbols=await upstream.channel(entry.isLive).symbols(id,session.access);
      return reply(res,200,{accountId:String(id),symbols},sessionHeader);
    }
    if(path==='/v1/candles'){
      const {id,entry}=await accountAccess(session,url);
      const symbolId=intArg(url,'symbolId',1,Number.MAX_SAFE_INTEGER);
      const periodName=url.searchParams.get('period');
      const period=PERIODS[periodName];
      if(!period)return fail(res,400,'unsupported_period');
      const from=intArg(url,'from',0,2147483646000),
            to=intArg(url,'to',from,2147483646000),
            count=intArg(url,'count',1,1000);
      if(to-from>90*86400000)return fail(res,400,'date_window_too_wide');
      const data=await upstream.channel(entry.isLive).history(id,session.access,symbolId,period,from,to,count);
      return reply(res,200,{symbolId:String(symbolId),period:periodName,source:'ctrader',...data},sessionHeader);
    }
    if(path==='/v1/spot'){
      const {id,entry}=await accountAccess(session,url);
      const symbolId=intArg(url,'symbolId',1,Number.MAX_SAFE_INTEGER);
      const quote=await getSpot(upstream.channel(entry.isLive),id,session.access,symbolId);
      return reply(res,200,{symbolId:String(symbolId),timestamp:Number(quote.timestamp||Date.now()),
        source:'ctrader',...(quote.bid==null?{}:{bid:Number(quote.bid)/1e5}),
        ...(quote.ask==null?{}:{ask:Number(quote.ask)/1e5})},sessionHeader);
    }
  }
  if(req.method==='POST'&&path==='/v1/logout')
    return reply(res,200,{linked:false,clientOnly:true,
      note:'Clear the Android session and revoke app access in cTrader portal if needed.'});
  return fail(res,404,'not_found');
}
const server=createServer((req,res)=>{
  Promise.resolve(handler(req,res)).catch(error=>{
    // Never send upstream URLs, tokens, stack traces, or encrypted credentials to clients.
    if(res.headersSent){res.end();return;}
    if(error.message==='unconfigured_gateway')return fail(res,503,'gateway_not_configured');
    if(error.message==='not_authenticated'||error.message==='invalid_session')
      return fail(res,401,'session_expired');
    if(error.message.startsWith('invalid_')||error.message==='account_not_authorized')
      return fail(res,400,'invalid_request');
    return fail(res,503,'broker_temporarily_unavailable');
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
            source:'ctrader',timestamp:Number(spot.timestamp||Date.now()),
            ...(spot.bid==null?{}:{bid:Number(spot.bid)/1e5}),
            ...(spot.ask==null?{}:{ask:Number(spot.ask)/1e5})}));
      });
    }catch{client.close(1008,'Unable to authorize cTrader stream');}
  });
  client.on('close',()=>{clearTimeout(timeout);unsubscribe?.();});
  client.on('error',()=>{clearTimeout(timeout);unsubscribe?.();});
});
export default server;
