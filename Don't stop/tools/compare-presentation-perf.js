'use strict';
// Compare the fixed presentation protocol without changing any threshold or raw input.
const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
if (!dir) throw new Error('Pass the directory containing raw and derived B11 reports.');
const pairs = [
  ['normal-1','before-warm-A-1-A','after-material-A-1-A'],
  ['normal-2','before-warm-A-2-A','after-material-A-2-A'],
  ['normal-3','before-warm-A-3-A','after-material-A-3-A'],
  // cache-dense-1 overlapped archive compression: retain it as a diagnostic and
  // use its explicitly recorded clean replacement, regardless of its outcome.
  ['dense-1','before-final-dense-D','after-cache-dense-clean-1-D'],
  ['dense-2','before-dense-repeat-D-D','after-cache-dense-2-D'],
  ['dense-3','before-dense-D-D','after-cache-dense-3-D'],
  ['mixed-1','before-final-mixed-D','after-material-mixed-1-D'],
  ['mixed-2','before-mixed-repeat-D-D','after-material-mixed-2-D'],
  ['mixed-3','before-mixed-corrected-D-D','after-material-mixed-3-D'],
  ['stage40-1','before-final-stage40-A','after-material-stage40-1-A'],
  ['stage40-2','before-stage40-repeat-A','after-material-stage40-2-A'],
  ['stage40-3','before-stage40-A','after-material-stage40-3-A'],
];
const read = (name,suffix) => JSON.parse(fs.readFileSync(path.join(dir,`stress-${name}${suffix}.json`),'utf8'));
function gate(before,after,limit) {
  return {before,after,delta:after-before,allowed_delta:limit,pass:after-before<=limit+1e-6};
}
function boss(raw) {
  const marker=raw.markers.find(s=>s.startsWith('[stress-boss] '));
  if (!marker) return null;
  const events=JSON.parse(marker.slice('[stress-boss] '.length));
  const phases=[...new Set(events.map(e=>e.phase))];
  const ultimate=Math.max(...events.map(e=>Number(e.ultimate_activated||0)));
  const starts=events.filter((e,i)=>i===0||e.round!==events[i-1].round||e.phase!==events[i-1].phase);
  const phase_samples=starts.map((e,i)=>{
    const begin=Math.max(0,e.frame-1),end=i+1<starts.length?starts[i+1].frame-1:raw.raw_frames.ms.length;
    const values=raw.raw_frames.ms.slice(begin,end),sorted=[...values].sort((a,b)=>a-b);
    const q=p=>sorted[Math.min(sorted.length-1,Math.floor(sorted.length*p))];
    return {round:e.round,phase:e.phase,frames:values.length,ms_total:values.reduce((a,b)=>a+b,0),
      p95:q(.95),p99:q(.99),max:sorted.at(-1),over33_3:values.filter(v=>v>33.3).length};
  });
  return {phases,ultimate_activations:ultimate,complete:phases.length===3&&ultimate>0,events,phase_samples};
}
const report={method:'Exact 15..105 combat-second hot windows; full/cold raw reports retained.',
  cpu_note:'Godot 4.7.2 publishes one-second maxima; these frame-weighted repeated gauges are not per-frame CPU durations. Proxy failures are retained.',
  memory:'N/A when the Web monitor reports zero; no zero-memory or GPU-time claim.',pairs:[]};
for (const [name,b,a] of pairs) {
  const before=read(b,'.warm'),after=read(a,'.warm'),br=read(b,''),ar=read(a,'');
  const gates={
    p95:gate(before.frame_ms.p95,after.frame_ms.p95,Math.max(.8,before.frame_ms.p95*.05)),
    p99:gate(before.frame_ms.p99,after.frame_ms.p99,Math.max(1.5,before.frame_ms.p99*.1)),
    over33_3:gate(before.frame_ms.over33_3,after.frame_ms.over33_3,2),
    physics_p95:gate(before.physics_ms.p95,after.physics_ms.p95,Math.max(.5,before.physics_ms.p95*.05)),
    process_p95:gate(before.process_ms.p95,after.process_ms.p95,Math.max(.5,before.process_ms.p95*.05)),
  };
  report.pairs.push({name,before:b,after:a,gates,
    numerical_gates_pass:Object.values(gates).every(g=>g.pass),
    over50:{before:before.frame_ms.over50,after:after.frame_ms.over50,
      repeatability_review_needed:after.frame_ms.over50>before.frame_ms.over50},
    before_frame:before.frame_ms,after_frame:after.frame_ms,
    before_draw_calls:before.draw_calls,after_draw_calls:after.draw_calls,
    before_load:before.full_run_peaks,after_load:after.full_run_peaks,
    before_boss:boss(br),after_boss:boss(ar),before_errors:br.errors,after_errors:ar.errors,
    before_build:br.build,after_build:ar.build});
}
fs.writeFileSync(path.join(dir,'presentation-comparison-final.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report.pairs.map(p=>({name:p.name,gates:p.gates,over50:p.over50,
  boss_complete:p.after_boss?.complete})),null,2));
