import test from 'node:test';
import assert from 'node:assert/strict';
import {authPage} from '../auth-page.mjs';

test('existing Android OAuth scheme is retained by default',()=>{
  const page=authPage('test_ticket');
  assert.match(page.body,/tradelab:\/\/oauth\/ctrader\?ticket=test_ticket/);
  assert.doesNotMatch(page.body,/tradelabflutter:\/\//);
});
test('Flutter OAuth is explicitly opt-in with an independent URI scheme',()=>{
  const page=authPage('test_ticket','flutter');
  assert.match(page.body,/tradelabflutter:\/\/oauth\/ctrader\?ticket=test_ticket/);
  assert.doesNotMatch(page.body,/href="tradelab:\/\//);
});
