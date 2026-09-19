'use strict';
// Derive the same exact 90-second hot window from B11's post-run raw samples.
// Does not alter the driver, discard failures, or replace the complete source report.
const fs = require('fs');
const path = require('path');
const inputs = process.argv.slice(2);
if (!inputs.length) throw new Error('Pass one or more B11 JSON reports with raw_frames.');
function stats(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a,b)=>a-b);
  const q = p => sorted[Math.min(sorted.length-1,Math.floor(sorted.length*p))];
  let longest = 0, run = 0;
  for (const ms of values) { run = ms > 33.3 ? run+ms : 0; longest=Math.max(longest,run); }
  return {n:values.length,p50:q(.5),p95:q(.95),p99:q(.99),max:sorted.at(-1),
    over25:values.filter(v=>v>25).length,over33_3:values.filter(v=>v>33.3).length,
    over50:values.filter(v=>v>50).length,longest_slow_run_ms:longest};
}
for (const input of inputs) {
  const source = JSON.parse(fs.readFileSync(input,'utf8'));
  const raw = source.raw_frames;
  if (!raw || !raw.ms?.length) throw new Error(`${input}: no raw frame samples; cannot infer a warm result`);
  const indices = [];
  let offset = 0, lastRound = raw.round[0], lastTime = 0, lastTotal = 0;
  for (let i=0;i<raw.ms.length;i++) {
    if (raw.round[i] !== lastRound) {offset += lastTime; lastRound=raw.round[i];}
    lastTime=raw.combat_seconds[i]; lastTotal=offset+lastTime;
    if (lastTotal>=15 && lastTotal<105) indices.push(i);
  }
  if (lastTotal<105) throw new Error(`${input}: incomplete 15s warmup + 90s measurement (${lastTotal}s)`);
  const pick = key => indices.map(i=>raw[key][i]);
  const result = {source:path.basename(input),build:source.build,gpu:source.gpu,scenario:source.scenario,
    protocol:{warmup_combat_seconds:15,window_combat_seconds:90,viewport:'1280x760',seed:20260918},
    frame_ms:stats(pick('ms')),physics_ms:stats(pick('physics_ms')),process_ms:stats(pick('process_ms')),
    draw_calls:((s)=>({n:s.n,p50:s.p50,p95:s.p95,p99:s.p99,max:s.max}))(stats(pick('draws'))),full_run_peaks:source.load,errors:source.errors,
    unavailable:{gpu_time_ms:'N/A: no GPU timer instrumentation',peak_window:'Peaks cover the full run, including warmup'},
    gates:{p95_delta_ms:'max(0.8, BEFORE * 0.05)',p99_delta_ms:'max(1.5, BEFORE * 0.10)',
      extra_over33_3:2,repeatable_new_over50:'not accepted',cpu_p95_delta_ms:'max(0.5, BEFORE * 0.05)'}};
  const output = input.replace(/\.json$/,'.warm.json');
  fs.writeFileSync(output,JSON.stringify(result,null,2));
  console.log(JSON.stringify({output,frame_ms:result.frame_ms,physics_ms:result.physics_ms,process_ms:result.process_ms}));
}
