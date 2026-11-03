import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import { randomToken, tokenHash, constantTimeEqual, makeCipher } from './security.mjs';
import { CTraderGateway, PERIODS } from './ctrader.mjs';

// An always-on HTTPS service behind a trusted TLS reverse proxy (e.g. Render/Railway).
// All cTrader credentials and tokens remain on this backend, never in Android.
const required=['PUBLIC_BASE_URL','DATABASE_URL','CTRADER_CLIENT_ID','CTRADER_CLIENT_SECRET','TOKEN_ENCRYPTION_KEY'];
for(const key of required)if(!process.env[key])throw new Error('Missing required environment variable: '+key);
const publicBase=process.env.PUBLIC_BASE_URL.replace(/\/$/,'');
if(new URL(publicBase).protocol!=='https:' || new URL(publicBase).pathname!=='/')
  throw new Error('PUBLIC_BASE_URL must be an HTTPS origin with no path');
const redirectUri=publicBase+'/auth/ctrader/callback';
const cipher=makeCipher(process.env.TOKEN_ENCRYPTION_KEY);
const pool=new Pool({connectionString:process.env.DATABASE_URL,max:10});
const gateway=new CTraderGateway(process.env.CTRADER_CLIENT_ID,process.env.CTRADER_CLIENT_SECRET);
const accountsCache=new Map();
const MAX_ACCOUNT_ID=Number.MAX_SAFE_INTEGER;
const START_CHALLENGE=/^[a-zA-Z0-9_-]{43}$/;
const readCookie=(req,name)=>(req.headers.cookie||'').split(';').map(v=>v.trim()).find(v=>v.startsWith(name+'='))?.slice(name.length+1)||'';
const cookie=(value,maxAge)=>`ct_flow=${value}; HttpOnly; Secure; SameSite=Lax; Path=/auth/ctrader; Max-Age=${maxAge}`;
const headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY'};
function send(res,status,body,contentType='application/json; charset=utf-8',extra={}) {
  res.writeHead(status,{...headers,...extra,'Content-Type':contentType});
  res.end(contentType.startsWith('application/json')?JSON.stringify(body):body);
}
function json(res,status,data){send(res,status,data);}
function fail(res,status,message){json(res,status,{error:message});}
function html(res,status,body,extra={}){send(res,status,body,'text/html; charset=utf-8',
 {...extra,'Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"});}
function redirect(res,url,extra={}){res.writeHead(302,{...headers,...extra,Location:url});res.end();}
async function readJson(req) {
  if(!req.headers['content-type']?.startsWith('application/json'))throw new Error('content_type');
  let content='';
  for await(const chunk of req) {
    content+=chunk.toString('utf8');
    if(content.length>4096)throw new Error('body_too_large');
  }
  return JSON.parse(content);
}
const validToken=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{43}$/.test(value);
async function accessSession(req) {
  const authorization=req.headers.authorization||'';
  if(!authorization.startsWith('Bearer '))return null;
  const token=authorization.slice(7);
  if(!validToken(token))return null;
  const r=await pool.query("SELECT * FROM ctrader_sessions WHERE session_hash=$1 AND revoked_at IS NULL",[tokenHash(token)]);
  return r.rows[0]||null;
}
async function fetchCTraderToken(params) {
  const url=new URL('https://openapi.ctrader.com/apps/token');
  for(const [key,value] of Object.entries({
    ...params,client_id:process.env.CTRADER_CLIENT_ID,client_secret:process.env.CTRADER_CLIENT_SECRET
  }))url.searchParams.set(key,String(value));
  // cTrader requires query parameters for this endpoint. Never log the URL or expose errors.
  const response=await fetch(url,{signal:AbortSignal.timeout(8000),headers:{Accept:'application/json'},cache:'no-store'});
  if(!response.ok)throw new Error('token_exchange_failed');
  const data=await response.json();
  if(data.errorCode||!data.accessToken||!data.refreshToken)throw new Error('token_exchange_failed');
  return data;
}
async function currentAccess(session) {
  if(new Date(session.token_expires_at).getTime()>Date.now()+5*60000)
    return cipher.decrypt(session.access_cipher);
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const current=(await client.query(
      "SELECT * FROM ctrader_sessions WHERE id=$1 AND revoked_at IS NULL FOR UPDATE",[session.id]
    )).rows[0];
    if(!current)throw new Error('session_revoked');
    if(new Date(current.token_expires_at).getTime()>Date.now()+5*60000) {
      await client.query('COMMIT');
      return cipher.decrypt(current.access_cipher);
    }
    const data=await fetchCTraderToken({grant_type:'refresh_token',refresh_token:cipher.decrypt(current.refresh_cipher)});
    await client.query(
      'UPDATE ctrader_sessions SET access_cipher=$1,refresh_cipher=$2,token_expires_at=$3 WHERE id=$4',
      [cipher.encrypt(data.accessToken),cipher.encrypt(data.refreshToken),
       new Date(Date.now()+Number(data.expiresIn)*1000),session.id]
    );
    await client.query('COMMIT');
    accountsCache.delete(session.id);
    return data.accessToken;
  } catch(e){await client.query('ROLLBACK');throw e;}
  finally{client.release();}
}
async function accounts(session) {
  const accessToken=await currentAccess(session);
  const cached=accountsCache.get(session.id);
  if(cached && cached.until>Date.now() && cached.accessHash===tokenHash(accessToken))
    return {accessToken,list:cached.list};
  const list=await gateway.accounts(accessToken);
  accountsCache.set(session.id,{list,accessHash:tokenHash(accessToken),until:Date.now()+30000});
  return {accessToken,list};
}
function accountNumber(value) {
  const n=Number(value);
  if(!Number.isSafeInteger(n)||n<1||n>MAX_ACCOUNT_ID)throw new Error('invalid_account');
  return n;
}
async function accountAccess(session,url) {
  const accountId=accountNumber(url.searchParams.get('accountId'));
  const {accessToken,list}=await accounts(session);
  const account=list.find(item=>item.accountId===String(accountId));
  if(!account)throw new Error('unauthorized_account');
  return {accountId,account,accessToken};
}
function numberArg(url,name,{min,max}) {
  const raw=url.searchParams.get(name);
  if(raw==null||raw==='')throw new Error('invalid_'+name);
  const value=Number(raw);
  if(!Number.isSafeInteger(value)||value<min||value>max)throw new Error('invalid_'+name);
  return value;
}
function makeReturnPage(ticket) {
  const deepLink=`tradelab://oauth/ctrader?ticket=${ticket}`;
  const nonce=randomToken();
  return {
    body:`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>TradeLab</title></head>
<body style="font-family:sans-serif;text-align:center;padding:36px;background:#071018;color:white">
<h2>تم تأكيد إذن القراءة من cTrader</h2>
<p>العودة إلى TradeLab لإكمال ربط حسابك. لا يتم تنفيذ أي صفقات حقيقية.</p>
<a href="${deepLink}" style="display:inline-block;background:#13a7a0;color:#001;padding:15px 20px;border-radius:10px">
فتح TradeLab</a>
<p>إذا لم يفتح التطبيق تلقائيًا، اضغط الزر.</p>
<script nonce="${nonce}">window.location.replace("${deepLink}")</script></body></html>`,
    nonce
  };
}
async function handle(req,res) {
  const url=new URL(req.url,'http://localhost');
  if(req.method==='GET'&&url.pathname==='/healthz')return json(res,200,{status:'ok',service:'tradelab-ctrader-gateway'});
  if(req.method==='GET'&&url.pathname==='/auth/ctrader/start') {
    const challenge=url.searchParams.get('challenge');
    if(!START_CHALLENGE.test(challenge||''))return fail(res,400,'invalid_challenge');
    const browser=randomToken();
    await pool.query('INSERT INTO oauth_flows (browser_hash,verifier_hash,expires_at) VALUES ($1,$2,now()+interval \'10 minutes\') ON CONFLICT (browser_hash) DO UPDATE SET verifier_hash=$2,expires_at=now()+interval \'10 minutes\'',
      [tokenHash(browser),challenge]);
    const authorizationUrl=new URL('https://id.ctrader.com/my/settings/openapi/grantingaccess/');
    authorizationUrl.searchParams.set('client_id',process.env.CTRADER_CLIENT_ID);
    authorizationUrl.searchParams.set('redirect_uri',redirectUri);
    authorizationUrl.searchParams.set('scope','accounts');
    authorizationUrl.searchParams.set('product','web');
    return redirect(res,authorizationUrl.toString(),{'Set-Cookie':cookie(browser,600)});
  }
  if(req.method==='GET'&&url.pathname==='/auth/ctrader/callback') {
    const browser=readCookie(req,'ct_flow');
    const clear={'Set-Cookie':cookie('',0)};
    if(!validToken(browser))return html(res,400,'<p>انتهت جلسة الربط. ارجع إلى التطبيق وحاول مرة أخرى.</p>',clear);
    const consumed=await pool.query(
      'DELETE FROM oauth_flows WHERE browser_hash=$1 AND expires_at>now() RETURNING verifier_hash',
      [tokenHash(browser)]
    );
    if(!consumed.rowCount)return html(res,400,'<p>جلسة الربط غير صالحة أو منتهية.</p>',clear);
    const code=url.searchParams.get('code');
    if(!code||code.length>2048||url.searchParams.has('error'))
      return html(res,400,'<p>تم إلغاء الربط أو لم يمنح cTrader إذن الوصول.</p>',clear);
    let auth;
    try { auth=await fetchCTraderToken({grant_type:'authorization_code',code,redirect_uri:redirectUri}); }
    catch { return html(res,502,'<p>تعذّر تأكيد التفويض. حاول مجددًا من التطبيق.</p>',clear); }
    const sessionId=randomUUID(), ticket=randomToken();
    const client=await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('INSERT INTO ctrader_sessions (id,access_cipher,refresh_cipher,token_expires_at) VALUES ($1,$2,$3,$4)',
        [sessionId,cipher.encrypt(auth.accessToken),cipher.encrypt(auth.refreshToken),
         new Date(Date.now()+Number(auth.expiresIn)*1000)]);
      await client.query(
        "INSERT INTO oauth_handoffs (ticket_hash,verifier_hash,session_id,expires_at) VALUES ($1,$2,$3,now()+interval '2 minutes')",
        [tokenHash(ticket),consumed.rows[0].verifier_hash,sessionId]
      );
      await client.query('COMMIT');
    }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
    const page=makeReturnPage(ticket);
    return html(res,200,page.body,{
      ...clear,'Content-Security-Policy':`default-src 'none'; script-src 'nonce-${page.nonce}'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'`
    });
  }
  if(req.method==='POST'&&url.pathname==='/auth/ctrader/redeem') {
    const body=await readJson(req);
    if(!validToken(body.ticket)||!validToken(body.verifier))return fail(res,400,'invalid_ticket');
    const client=await pool.connect();
    try{
      await client.query('BEGIN');
      const result=await client.query(
        'SELECT ticket_hash,verifier_hash,session_id FROM oauth_handoffs WHERE ticket_hash=$1 AND expires_at>now() FOR UPDATE',
        [tokenHash(body.ticket)]
      );
      if(!result.rowCount||!constantTimeEqual(result.rows[0].verifier_hash,tokenHash(body.verifier))) {
        await client.query('ROLLBACK');
        return fail(res,401,'invalid_or_expired_ticket');
      }
      const sessionToken=randomToken();
      await client.query('DELETE FROM oauth_handoffs WHERE ticket_hash=$1',[tokenHash(body.ticket)]);
      await client.query('UPDATE ctrader_sessions SET session_hash=$1 WHERE id=$2',
        [tokenHash(sessionToken),result.rows[0].session_id]);
      await client.query('COMMIT');
      return json(res,200,{sessionToken,permission:'read_only'});
    }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
  }
  if(url.pathname.startsWith('/v1/')) {
    const session=await accessSession(req);
    if(!session)return fail(res,401,'not_authenticated');
    if(req.method==='GET'&&url.pathname==='/v1/session')
      return json(res,200,{linked:true,permission:'read_only'});
    if(req.method==='POST'&&url.pathname==='/v1/logout') {
      await pool.query('UPDATE ctrader_sessions SET revoked_at=now(),session_hash=NULL WHERE id=$1',[session.id]);
      accountsCache.delete(session.id);
      return json(res,200,{linked:false});
    }
    if(req.method==='GET'&&url.pathname==='/v1/accounts') {
      const result=await accounts(session);
      return json(res,200,{accounts:result.list});
    }
    if(req.method==='GET'&&url.pathname==='/v1/symbols') {
      const {accountId,account,accessToken}=await accountAccess(session,url);
      const symbols=await gateway.channel(account.isLive).symbols(accountId,accessToken);
      return json(res,200,{accountId:String(accountId),symbols});
    }
    if(req.method==='GET'&&url.pathname==='/v1/candles') {
      const {accountId,account,accessToken}=await accountAccess(session,url);
      const symbolId=numberArg(url,'symbolId',{min:1,max:MAX_ACCOUNT_ID});
      const period=PERIODS[url.searchParams.get('period')];
      if(!period)return fail(res,400,'unsupported_period');
      const now=Date.now(),from=numberArg(url,'from',{min:0,max:2147483646000});
      const to=numberArg(url,'to',{min:from,max:Math.min(now+86400000,2147483646000)});
      if(to-from>90*86400000)return fail(res,400,'date_window_too_wide');
      const count=numberArg(url,'count',{min:1,max:1000});
      const data=await gateway.channel(account.isLive).history(accountId,accessToken,symbolId,period,from,to,count);
      return json(res,200,{symbolId:String(symbolId),period:url.searchParams.get('period'),source:'ctrader',...data});
    }
    if(req.method==='GET'&&url.pathname==='/v1/spot') {
      const {accountId,account,accessToken}=await accountAccess(session,url);
      const symbolId=numberArg(url,'symbolId',{min:1,max:MAX_ACCOUNT_ID});
      let unsubscribe=()=>{};
      try {
        const spot=await new Promise(async(resolve,reject)=>{
          const timer=setTimeout(()=>reject(new Error('spot_timeout')),15000);
          try{
            unsubscribe=await gateway.channel(account.isLive).subscribe(accountId,accessToken,symbolId,raw=>{
              clearTimeout(timer);resolve(raw);
            });
          }catch(e){clearTimeout(timer);reject(e);}
        });
        const quote={symbolId:String(symbolId),timestamp:Number(spot.timestamp||Date.now()),source:'ctrader'};
        if(spot.bid!=null)quote.bid=Number(spot.bid)/100000;
        if(spot.ask!=null)quote.ask=Number(spot.ask)/100000;
        return json(res,200,quote);
      }finally{unsubscribe();}
    }
  }
  return fail(res,404,'not_found');
}
const server=http.createServer((req,res)=>{
  Promise.resolve(handle(req,res)).catch(err=>{
    // Do not leak tokens, secret URLs, upstream errors or database details in HTTP responses/logs.
    if(res.headersSent){res.end();return;}
    if(/^invalid_|^unauthorized_account$|^unsupported_period$/.test(err.message))
      return fail(res,400,err.message);
    if(err.message==='session_revoked')return fail(res,401,'session_expired');
    return fail(res,503,'service_unavailable');
  });
});
const port=Number(process.env.PORT||8080);
server.listen(port,()=>console.info(`TradeLab cTrader gateway listening on port ${port}`));
setInterval(()=>pool.query("DELETE FROM oauth_flows WHERE expires_at<now();").catch(()=>{}),3600000).unref();
setInterval(()=>pool.query("DELETE FROM oauth_handoffs WHERE expires_at<now();").catch(()=>{}),3600000).unref();
