'use strict';
// Offline analysis only: read immutable raw archive; never replace acceptance windows.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const assert = require('assert');
const dir = process.argv[2];
if (!dir) throw new Error('Pass the presentation evidence directory.');
const archive = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(dir, 'performance-raw.json.gz'))));
const comparison = JSON.parse(fs.readFileSync(path.join(dir, 'performance-comparison.json')));
const quantile = values => [...values].sort((a,b)=>a-b)[Math.floor(values.length*.95)];
const output = {method:'Offline existing raw data. Unchanged 15 <= cumulative combat seconds < 105. Frame indices are one-based. Event proximity is not attribution.',
  limitations:['CPU samples repeat published one-second maxima, not per-frame durations.',
    'Per-second producer timers are interval totals, not frame-level spans; report times are rounded to 0.1s.',
    'No browser scheduling, GPU spans, allocation stacks or per-frame weapon/VFX attribution was captured.'],pairs:[]};
for (const pair of comparison.pairs.filter(p=>/^(dense|mixed|stage40)/.test(p.name))) {
  const result = {name:pair.name,gates:pair.gates,runs:{}};
  for (const side of ['before','after']) {
    const filename = `stress-${pair[side]}.json`;
    assert(archive[filename], filename);
    const source = JSON.parse(archive[filename]), raw = source.raw_frames;
    let offset=0, lastRound=raw.round[0], lastTime=0;
    const times=raw.ms.map((_,i)=>{
      if (raw.round[i]!==lastRound) {offset+=lastTime;lastRound=raw.round[i];}
      lastTime=raw.combat_seconds[i];return offset+lastTime;
    });
    const hot=times.map((t,i)=>t>=15&&t<105?i:-1).filter(i=>i>=0);
    assert(times.at(-1)>=105);
    for (const [field,gate] of [['ms','p95'],['physics_ms','physics_p95'],['process_ms','process_p95']])
      assert(Math.abs(quantile(hot.map(i=>raw[field][i]))-pair.gates[gate][side])<1e-6,`${pair.name} ${side} ${field}`);
    let reportEnd=0;
    const reports=source.per_second.map(r=>{const start=reportEnd;reportEnd+=Number(r.n);return {...r,first_frame:start+1,last_frame:reportEnd};});
    assert(reportEnd<=raw.ms.length);
    for (const r of reports) {
      const samples=raw.ms.slice(r.first_frame-1,r.last_frame);
      assert(Math.abs(Math.max(...samples)-Number(r.max))<=.011,`${filename}: report/frame alignment`);
      assert(samples.filter(v=>v>50).length===Number(r.over50),`${filename}: interval long-frame count`);
    }
    const bossMarker=source.markers.find(m=>m.startsWith('[stress-boss] '));
    const boss=bossMarker?JSON.parse(bossMarker.slice(14)):[];
    const weapons=source.markers.filter(m=>m.startsWith('[stress] weapon=')).map(m=>{
      const v=Object.fromEntries([...m.matchAll(/(weapon|round|combat_s)=([\d.]+)/g)].map(x=>[x[1],Number(x[2])]));
      // The driver's misleading combat_s marker is round-local elapsed, not cumulative.
      v.round_s=v.combat_s;delete v.combat_s;return v;
    });
    const point=i=>({frame:i+1,round:raw.round[i],round_s:raw.combat_seconds[i],combat_s:times[i],ms:raw.ms[i]});
    const longs=raw.ms.flatMap((ms,i)=>{
      if(ms<=50)return [];
      const same=reports.filter(r=>Number(r.r)===raw.round[i]);
      const near=same.filter(r=>Math.abs(Number(r.t)-raw.combat_seconds[i])<=1.2);
      const weapon=weapons.filter(w=>w.round===raw.round[i]&&w.round_s<=raw.combat_seconds[i]+.005).at(-1);
      const event=boss.filter(e=>e.frame<=i+1).at(-1);
      return [{...point(i),hot:times[i]>=15&&times[i]<105,
        neighbors:raw.ms.slice(Math.max(0,i-2),i+3),nearby_interval_reports:near,
        containing_interval_report:reports.find(r=>r.first_frame<=i+1&&r.last_frame>=i+1)??null,
        last_weapon_marker:weapon??null,seconds_since_weapon_marker:weapon?raw.combat_seconds[i]-weapon.round_s:null,
        last_boss_event:event??null}];
    });
    const proxies={};
    for(const [field,gate] of [['physics_ms','physics_p95'],['process_ms','process_p95']]) {
      const threshold=pair.gates[gate].before+pair.gates[gate].allowed_delta;
      const segments=[];
      for(const i of hot.filter(i=>raw[field][i]>threshold+1e-6)) {
        const prev=segments.at(-1);
        if(prev&&prev.end.frame===i&&prev.end.round===raw.round[i]&&prev.value_ms===raw[field][i]) {
          prev.end=point(i);prev.frames++;
        } else segments.push({value_ms:raw[field][i],frames:1,start:point(i),end:point(i)});
      }
      proxies[field]={threshold_ms:threshold,above_threshold_frames:segments.reduce((s,r)=>s+r.frames,0),hot_frames:hot.length,segments};
    }
    result.runs[side]={source:filename,build:source.build,proxies,long_frames:longs,weapon_markers:weapons,boss_events:boss};
  }
  output.pairs.push(result);
}
fs.writeFileSync(path.join(dir,'performance-tail-analysis.json'),JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify(output.pairs.map(p=>({name:p.name,...Object.fromEntries(['before','after'].map(side=>[side,{
  hotLongs:p.runs[side].long_frames.filter(f=>f.hot).map(f=>({t:f.combat_s,r:f.round,ms:f.ms,weapon:f.last_weapon_marker,since:f.seconds_since_weapon_marker})),
  proxy:Object.fromEntries(Object.entries(p.runs[side].proxies).map(([key,v])=>[key,{above:v.above_threshold_frames,total:v.hot_frames,segments:v.segments.length}]))
}]))})),null,2));
