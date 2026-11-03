import test from 'node:test';
import assert from 'node:assert/strict';
import {isReadOnlyScope,normalizeBar} from '../ctrader.mjs';

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
