import test from 'node:test';
import assert from 'node:assert/strict';
import {isReadOnlyScope,normalizeBar,mergeReadOnlyAccountLists} from '../ctrader.mjs';

test('read-only grants accept optional scope but explicitly deny trade permission',()=>{
    assert.equal(isReadOnlyScope(undefined),true);
    assert.equal(isReadOnlyScope(null),true);
    assert.equal(isReadOnlyScope(0),true);
    assert.equal(isReadOnlyScope('SCOPE_VIEW'),true);
    assert.equal(isReadOnlyScope(1),false);
    assert.equal(isReadOnlyScope('SCOPE_TRADE'),false);
});
test('cTrader trendbar normalizer requires actual price fields',()=>{
    const bar=normalizeBar({low:230000000,deltaOpen:30000,
        deltaHigh:50000,deltaClose:20000,utcTimestampInMinutes:29000000,volume:65});
    assert.equal(bar.open,2300.3);
    assert.equal(bar.high,2300.5);
    assert.equal(bar.close,2300.2);
    assert.equal(bar.volume,65);
    assert.equal(bar.timestamp,29000000*60_000);
});

test('merge demo and live authorized accounts without dropping one or duplicating both',()=>{
    const demo={permissionScope:'SCOPE_VIEW',ctidTraderAccount:[
        {ctidTraderAccountId:101,isLive:false,brokerTitleShort:'Demo Broker',traderLogin:12345}
    ]};
    const live={permissionScope:0,ctidTraderAccount:[
        {ctidTraderAccountId:202,isLive:true,brokerTitleShort:'Live Broker',traderLogin:98765},
        {ctidTraderAccountId:101,isLive:false,brokerTitleShort:'Demo Broker',traderLogin:12345}
    ]};
    const accounts=mergeReadOnlyAccountLists([demo,live]);
    assert.equal(accounts.length,2);
    assert.deepEqual(accounts.map(a=>a.accountId).sort(),['101','202']);
    assert.equal(accounts.find(a=>a.accountId==='202').isLive,true);
    assert.equal(accounts.find(a=>a.accountId==='101').isLive,false);
});

test('never use account list with an explicit trading scope',()=>{
    assert.throws(()=>mergeReadOnlyAccountLists([
      {permissionScope:'SCOPE_TRADE',ctidTraderAccount:[{ctidTraderAccountId:123,isLive:true}]}
    ]),/ctrader_view_only_required/);
});

test('empty and malformed accounts do not cause phantom connections',()=>{
    const accounts=mergeReadOnlyAccountLists([
       {ctidTraderAccount:[{ctidTraderAccountId:'nope',isLive:true}]},
       {ctidTraderAccount:[]}
    ]);
    assert.deepEqual(accounts,[]);
});
