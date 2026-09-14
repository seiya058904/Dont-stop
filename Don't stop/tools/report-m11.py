"""Compile only recorded M11 evidence; missing or failed gates remain incomplete."""
import ast
import csv
import hashlib
import json
import pathlib
import re
import subprocess

root=pathlib.Path(__file__).resolve().parents[1]
out=root/'docs/iteration/evidence/m11'
anchor='928db1cdc16e1b181527878af602d40b35e17f12'
def read(path): return json.loads((out/path).read_text(encoding='utf-8'))
def write(path,data): (out/path).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def source(path): return (root/path).read_text(encoding='utf-8-sig').replace('\r\n','\n')
def old(path): return subprocess.check_output(['git','show',f'{anchor}:{root.name}/{path}'],cwd=root).decode('utf-8').replace('\r\n','\n')
def section(text,name): return re.search(r'const '+name+r' = (\{.*?^\})',text,re.M|re.S)[1]
def checked(label):
    path=out/label/'execution.json'
    if not path.exists(): return dict(label=label,passed=False,missing=True,checks=0)
    execution=read(f'{label}/execution.json'); log=(out/label/'run.txt').read_text(encoding='utf-8')
    leaks=re.findall(r'Leaked instance: (\w+):',log)
    known=sorted(leaks)==['AudioStreamMP3','AudioStreamPlaybackMP3'] and 'Cephalopod.mp3' in log
    errors=[e for e in execution['errors'] if not (known and e.startswith('ERROR: 1 resources still in use at exit'))]
    if 'SCRIPT ERROR:' in log: errors.append('SCRIPT ERROR in raw log')
    checks=len(re.findall(r'^PASS ',log,re.M))
    if 'MAIN EXIT CLICK DISPATCHED' in log: checks=1
    return dict(label=label,passed=execution['code']==0 and checks>0 and not errors and (not leaks or known),checks=checks,errors=errors,known_audio_teardown=known)

content=source('game/config/M5Content.gd'); previous=old('game/config/M5Content.gd')
catalog=source('game/config/WeaponCatalog.gd')
contracts={name+'_unchanged':section(content,name)==section(previous,name) for name in ['ENEMIES','BOSSES','REGIONS','WALLS']}
contracts['early_and_boss_encounters_unchanged']=all(re.search(r'^\t\t'+str(i)+r':.*$',content,re.M)[0]==re.search(r'^\t\t'+str(i)+r':.*$',previous,re.M)[0] for i in list(range(1,21))+[30])
for path in ['game/config/WeaponCatalog.gd','game/config/AttachmentCatalog.gd','game/config/DemoConfig.gd','autoload/server/RewardServer.gd']:
    contracts[path+'_unchanged']=source(path)==old(path)
contracts['counts']={'weapons':len(ast.literal_eval(re.search(r'^const TIERS = (.*)$',catalog,re.M)[1])), 'enemies':len(re.findall(r'"E\d+":',section(content,'ENEMIES'))),'bosses':len(re.findall(r'"B\d+":',section(content,'BOSSES'))),'regions':len(re.findall(r'"R\d+":',section(content,'REGIONS'))),'encounters':len(re.findall(r'^\t\t\d+:',content,re.M))}
contracts['counts_preserved']=contracts['counts']==dict(weapons=24,enemies=12,bosses=3,regions=6,encounters=30)
contracts['upgrades_24']=len(ast.literal_eval(re.search(r'^const PRICES = (.*)$',source('game/config/AttachmentCatalog.gd'),re.M)[1]))==24
contracts['talents_24']=len(re.findall(r'"T\d+":',section(source('game/config/DemoConfig.gd'),'TALENTS')))==24
contracts['rewards_24']=len(re.findall(r'^\s*"\d+" = preload',source('autoload/server/RewardServer.gd'),re.M))==24
write('source-contracts.json',contracts)

labels=['clarity-source-final','genuine-save-migration','horde-contracts-final','spawn-final','navigation-final','legacy-visual','boss-high-repeat']
labels += ['legacy-perf-'+s for s in ['normal','late','density','boss','boss-barrage','projectile','telegraph','particle']]
labels += ['native-baseline-C','native-final-C','native-final-B']
labels += ['baseline-A','baseline-good-B','baseline-C','horde-final-A','horde-final-B','horde-final-C']
runs=[checked(label) for label in labels]
regressions=read('regression.json') if (out/'regression.json').exists() else []
# Keep the complete first run intact. The independent Boss 30 rerun resolves only
# that one failed assertion; other stages/actions must pass in the original run.
regression_resolution=[]
for row in regressions:
    resolved=dict(row)
    if row['scene']=='M10Bosses' and row['args']==['high'] and row['errors']==['FAIL boss clear and both phases 30']:
        retry=checked('boss-high-repeat')
        resolved['passed']=retry['passed']; resolved['independent_repeat']=retry
    regression_resolution.append(resolved)
write('regression-resolution.json',regression_resolution)

pressure=[]; profiles={}
for build,base in [('A','baseline-A'),('B','baseline-good-B'),('C','baseline-C')]:
    final=f'horde-final-{build}'
    if not (out/final/'m11/horde.json').exists(): continue
    b=read(f'{base}/m11/horde.json'); f=read(f'{final}/m11/horde.json'); profiles[build]=f['build']
    for before,after in zip(b['rows'],f['rows']):
        assert before['stage']==after['stage']
        pressure.append(dict(build=build,stage=after['stage'],baseline=before,final=after,
            mean_increase_percent=100*(after['alive']['mean']/before['alive']['mean']-1),spawn_increase_percent=100*(after['spawn_rate']/before['spawn_rate']-1)))
write('pressure-comparison.json',pressure); write('legal-builds.json',profiles)
flat=[]
for pair in pressure:
    for version in ['baseline','final']:
        row=pair[version]; item=dict(build=pair['build'],stage=pair['stage'],version=version)
        for key,value in row.items():
            if isinstance(value,dict): item.update({key+'_'+k:v for k,v in value.items()})
            elif not isinstance(value,list): item[key]=value
        flat.append(item)
if flat:
    with (out/'pressure-all-metrics.csv').open('w',encoding='utf-8-sig',newline='') as file:
        writer=csv.DictWriter(file,fieldnames=list(dict.fromkeys(k for row in flat for k in row))); writer.writeheader(); writer.writerows(flat)
performance=[]
for label in labels:
    path=out/label/'m10/perf.json'
    if path.exists(): performance.append(dict(label=label,metrics=json.loads(path.read_text(encoding='utf-8')),validation=checked(label)))
native=[]
for label in ['native-baseline-C','native-final-C','native-final-B']:
    if (out/label/'m11/horde.json').exists(): native.append(dict(label=label,**read(f'{label}/m11/horde.json')))
write('performance.json',dict(legacy=performance,active_fire=native,historical_m9_max_ms=55.126,historical_m10_max_ms=38.785))
final_source=out/'clarity-source-final/execution.json'
source_drift=[]
if final_source.exists():
    for path,digest in read('clarity-source-final/execution.json')['source'].items():
        if path.startswith(('game/','autoload/','ui/')) and (not (root/path).exists() or hashlib.sha256((root/path).read_bytes()).hexdigest()!=digest): source_drift.append(path)
gates=dict(final_product_source_verified=final_source.exists() and not source_drift,content_frozen=all(v for v in contracts.values() if isinstance(v,bool)),required_runs_pass=all(r['passed'] for r in runs),
    old_regressions_pass=len(regression_resolution)==32 and all(r['passed'] for r in regression_resolution),
    three_builds_seven_stages=len(pressure)==21 and all(not p['failures'] for p in profiles.values()),
    active_safe_arrivals=len(pressure)==21 and all(r['final']['shots']>0 and r['final']['illegal_spawns']==0 for r in pressure),
    sustained_mature_late_horde=all(r['final']['alive']['mean']>=20 and r['final']['longest_dead_air']<2 for r in pressure if r['build']=='B' and r['stage']>=27) and len(pressure)==21,
    native_performance_recorded=len(performance)==8 and len(native)==3 and all(r['metrics']['draw_calls']>0 for r in performance) and all(row.get('viewport_draw_peak',0)>0 for run in native for row in run['rows']))
ready=all(gates.values())
summary=dict(status='M11 DIFFICULTY & CLARITY COMPLETE / READY FOR FINAL HUMAN ACCEPTANCE' if ready else 'M11 EVIDENCE INCOMPLETE',H1_STATUS='FOURTH_FEEDBACK_ADDRESSED' if ready else 'INCOMPLETE',HUMAN_ACCEPTED=False,anchor=anchor,gates=gates,runs=runs,
    final_product_source_drift=source_drift,
    limitations=['Automated omniscient aiming and real inputs are engineering evidence, not human acceptance.','Stationary mature bot survives 45 seconds; persistent living horde is demonstrated, mandatory movement is not proved.','Rare cold spikes and congestion observations remain in raw evidence.'])
write('summary.json',summary)
def table(headers,rows): return '| '+' | '.join(headers)+' |\n|'+'|'.join(['---']*len(headers))+'|\n'+''.join('| '+' | '.join(map(str,row))+' |\n' for row in rows)
text='# M11 测量索引\n\n自动生成；原始失败与复测分开保留。所有时间单位毫秒或字段所示秒。\n\n'+summary['status']+'\n\n'
text+='## 开火构筑对照\n\n'+table(['构筑/关','平均存活 M10→M11','median/p90/peak M11','spawn/s M10→M11','kill/s','接战/s','近身均值','<5秒 / 空场最长秒','损血/死亡/时长秒'],[[f"{r['build']}/{r['stage']}",f"{r['baseline']['alive']['mean']:.2f} → {r['final']['alive']['mean']:.2f}",f"{r['final']['alive']['median']}/{r['final']['alive']['p90']}/{r['final']['alive']['peak']}",f"{r['baseline']['spawn_rate']:.2f} → {r['final']['spawn_rate']:.2f}",f"{r['final']['kill_rate']:.2f}",f"{r['final']['engagement200_rate']:.2f}",f"{r['final']['close120']['mean']:.2f}",f"{r['final']['below_five_seconds']:.2f}/{r['final']['longest_dead_air']:.2f}",f"{r['final']['hp_loss']:.2f}/{r['final']['death']}/{r['final']['seconds']:.2f}"] for r in pressure])
text+='\n## 独占原生开火性能\n\n'+table(['运行/关','CPU mean/p50/p95/p99/max','帧 p50/p95/p99/max','含冷启动max','玩家弹/敌弹/玩家FX/敌FX','导航/出生寻路','CANVAS峰值'],[[f"{run['label']}/{r['stage']}",'/'.join(f"{r['cpu_ms'][k]:.3f}" for k in ['mean','median','p95','p99','peak']),'/'.join(f"{r['frame_ms'][k]:.3f}" for k in ['median','p95','p99','peak']),f"{r['including_cold_max_ms']:.3f}",'/'.join(str(r.get(k,'N/A')) for k in ['player_projectile_peak','enemy_projectile_peak','player_vfx_peak','vfx_peak']),f"{r['path_queries']}/{r['spawn_path_queries']}" if r.get('navigation_instrumented') else 'N/A (M10无计数器)',r.get('viewport_draw_peak','N/A')] for run in native for r in run['rows']])
text+='\n## 保留性能场景\n\n'+table(['场景','p50/p95/p99/max','draw calls'],[[r['metrics']['scenario'],'/'.join(f"{r['metrics'][k]:.3f}" for k in ['p50','p95','p99','max']),r['metrics']['draw_calls']] for r in performance])
text+='\n## 运行检查\n\n'+table(['场景','检查数','通过','已知MP3退出'],[[r['label'],r['checks'],r['passed'],r.get('known_audio_teardown',False)] for r in runs])
text+='\n完整原始指标见 pressure-all-metrics.csv、pressure-comparison.json、performance.json；合法实际购买清单见 legal-builds.json。旧回归首轮见 regression.json，逐项复测判定见 regression-resolution.json。\n'
(out/'README.md').write_text(text,encoding='utf-8')
print(json.dumps(summary['gates'],indent=2)); print(summary['status'])
raise SystemExit(0 if ready else 1)
