'use strict';
// No Flutter/Dart imports; deterministic input and analytic weighted sum.
// Run from anywhere: node tools/pine/generate_stage3b_reference.cjs [--check]
const fs = require('node:fs');
const path = require('node:path');
function makeReference(){
  // Independent finite weighted sum, not the application's recurrent state.
  const seed=20261124, count=360;
  let state=seed>>>0;
  function rand(){state=(Math.imul(1664525,state)+1013904223)>>>0;return state/4294967296;}
  const range=(lo,hi)=>lo+Math.floor(rand()*(hi-lo+1));
  let previous=195000;
  const bars=[];
  for(let i=0;i<count;i++){
    const regime=i<90?7:i<180?-9:i<270?0:12;
    const gap=i%41===0&&i!==0?range(-180,180):range(-6,6);
    const open=previous+gap;
    const close=i>=180&&i<200?previous:open+regime+range(-65,65);
    const high=Math.max(open,close)+range(2,45);
    const low=Math.min(open,close)-range(2,45);
    const volume=range(80,1500)+Math.abs(close-open)*9;
    bars.push([open/100,high/100,low/100,close/100,volume]);previous=close;
  }
  const closes=bars.map(b=>b[3]);
  const tr=bars.map((b,i)=>i===0?b[1]-b[2]:Math.max(b[1]-b[2],Math.abs(b[1]-closes[i-1]),Math.abs(b[2]-closes[i-1])));
  const gains=closes.slice(1).map((v,i)=>Math.max(0,v-closes[i]));
  const losses=closes.slice(1).map((v,i)=>Math.max(0,closes[i]-v));
  function weighted(xs, alpha, seedCount, index){
    if(index<seedCount-1)return null;
    const origin=xs.slice(0,seedCount).reduce((a,b)=>a+b,0)/seedCount;
    const decay=1-alpha;
    // Analytic expansion of exponential smoothing with Kahan summation.
    let sum=origin*Math.pow(decay,index-seedCount+1), correction=0;
    for(let k=seedCount;k<=index;k++){
      const term=alpha*xs[k]*Math.pow(decay,index-k);
      const y=term-correction, next=sum+y;
      correction=(next-sum)-y;sum=next;
    }
    return sum;
  }
  const round=v=>v===null?null:Number(v.toFixed(9));
  const series={};
  for(const n of [14,50]){
    const outputs={"ta.ema":[],"ta.rsi":[],"ta.atr":[],"ta.rma":[]};
    for(let i=0;i<count;i++){
      outputs["ta.ema"].push(round(weighted(closes,2/(n+1),1,i)));
      outputs["ta.rma"].push(round(weighted(closes,1/n,n,i)));
      outputs["ta.atr"].push(round(weighted(tr,1/n,n,i)));
      const g=weighted(gains,1/n,n,i-1),l=weighted(losses,1/n,n,i-1);
      outputs["ta.rsi"].push(round(g===null||l===null?null:l===0?100:100*g/(g+l)));
    }
    series[String(n)]=outputs;
  }
  return {schemaVersion:1,source:"independent synthetic OHLCV, not broker or TradingView data",generator:"tools/pine/generate_stage3b_reference.cjs",seed,prng:"LCG uint32: state = (1664525*state+1013904223) mod 2^32",barCount:count,columns:["open","high","low","close","volume"],checkpointsOneBased:[1,10,50,300,360],lengths:[14,50],bars,expected:series};
}
const target=path.resolve(__dirname,'../../flutter_app/test/fixtures/pine_stage3b_ohlcv_long.json');
const output=JSON.stringify(makeReference(),null,2)+'\n';
if(process.argv.includes('--check')){
  if(!fs.existsSync(target)||fs.readFileSync(target,'utf8')!==output){
    console.error('Independent reference fixture differs; review and regenerate deliberately.');
    process.exitCode=1;
  }else console.log('Independent 360-bar reference fixture reproduced byte-for-byte.');
}else{
  fs.writeFileSync(target,output);
  console.log('Wrote '+target);
}
