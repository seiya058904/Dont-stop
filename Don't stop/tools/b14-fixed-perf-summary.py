"""Summarize the paired native fixture without moving its 15..105s window."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]/'evidence/visual-upgrade-20260919'
def stats(values):
    v=sorted(values)
    def q(p):return v[min(len(v)-1,int((len(v)-1)*p))]
    return dict(n=len(v),mean=sum(v)/len(v),p95=q(.95),p99=q(.99),max=max(v),over33_3=sum(x>33.3 for x in v),over50=sum(x>50 for x in v))
pair={}
for tag in ['before','after']:
    data=json.loads((root/f'b14-fixed-perf-{tag}.json').read_text(encoding='utf-8-sig'))
    rows=[r for r in data['rows'] if 15<=r[0]<=105]
    pair[tag]={'renderer':data['renderer'],'window':[15,105],'zones_emitted':data['zones_emitted'],'transient_peak':data['transient_peak'],
        'frame':stats([r[1] for r in rows]),'process_proxy':stats([r[2] for r in rows]),'physics_proxy':stats([r[3] for r in rows]),
        'draw_calls':stats([r[4] for r in rows]),'full_timeline_max_ms':max(r[1] for r in data['rows']),
        'long_frames':[{'elapsed':r[0],'ms':r[1],'in_original_window':15<=r[0]<=105} for r in data['rows'] if r[1]>33.3]}
gates={}
for metric,key,floor,ratio in [('frame','p95',.8,.05),('frame','p99',1.5,.1),('process_proxy','p95',.5,.05),('physics_proxy','p95',.5,.05)]:
    b=pair['before'][metric][key];a=pair['after'][metric][key];limit=max(floor,b*ratio)
    gates[metric+'_'+key]={'before':b,'after':a,'allowed_delta':limit,'pass':a-b<=limit+1e-6}
gates['extra_over33_3']={'delta':pair['after']['frame']['over33_3']-pair['before']['frame']['over33_3'],'allowed':2}
gates['extra_over33_3']['pass']=gates['extra_over33_3']['delta']<=2
out={'method':'Windows native Godot Forward+/Vulkan, one fixed technical pair, no simultaneous screenshots or other owned test workloads',
    'pair':pair,'gates':gates,'true_per_frame_cpu':'N/A','gpu_ms':'N/A',
    'limitations':'One pair is not repeatability proof. Per-second published CPU maxima are proxies, not independent frame timings. Gameplay workload, historic Web three FAILs and long-frame attribution remain separate; no exemption.'}
(root/'b14-fixed-perf-comparison.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'gates':gates,'full_max':[pair[t]['full_timeline_max_ms'] for t in pair]},ensure_ascii=False,indent=2))
