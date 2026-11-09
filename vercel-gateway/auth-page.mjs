import {randomToken} from './session.mjs';

export function authPage(ticket, client='native') {
  const scheme=client==='flutter'?'tradelabflutter':'tradelab';
  const uri=scheme+'://oauth/ctrader?ticket='+encodeURIComponent(ticket);
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
