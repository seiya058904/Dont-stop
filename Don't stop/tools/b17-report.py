"""Reduce actual B17 observations; never turn a missing observation into a pass."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / 'evidence/visual-upgrade-20260919'
OUT = ROOT / 'docs/iteration/evidence/b17'
OUT.mkdir(parents=True, exist_ok=True)

def read(name):
    return json.loads((RAW/name).read_text(encoding='utf-8'))

def write(name, value):
    (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=1)+'\n', encoding='utf-8')

def times(values):
    values = sorted(values)
    if not values:
        return {'status': 'NO_SAMPLES'}
    return dict(samples=len(values), **{k: round(values[min(len(values)-1, int(len(values)*q))], 3)
                                       for k, q in [('p50', .5), ('p95', .95), ('p99', .99), ('max', 1)]},
                over25=sum(x>25 for x in values), over33=sum(x>33.3 for x in values), over50=sum(x>50 for x in values))

performance = {}
for name in ['b17-capacity-before.json', 'b17-product-perf.json', 'b17-density-paired.json']:
    if not (RAW/name).exists():
        performance[name] = {'status':'NOT_RUN'}
        continue
    summaries=[]
    for row in read(name):
        summary={k:v for k,v in row.items() if k not in ['frames','counts']}
        summary['warm_frame_ms']=times([f[1] for f in row['frames'] if f[0]>=5])
        summary['all_frame_ms']=times([f[1] for f in row['frames']])
        for field in ['ordinary','enemies','enemy_shots','nodes','transients']:
            values=[c[field] for c in row['counts'] if field in c]
            if values: summary[field]=times(values)
        summaries.append(summary)
    performance[name]=summaries
fixed=RAW/'b14-fixed-perf-b17.json'
if fixed.exists():
    row=read(fixed.name)
    performance['fixed']={'frame_ms':times([f[1] for f in row['rows'] if 15<=f[0]<=105]),
                          'process_proxy_ms':times([f[2] for f in row['rows'] if 15<=f[0]<=105]),
                          'zones_emitted':row['zones_emitted'],'true_per_frame_cpu':None,'gpu_ms':None}
write('performance.json',performance)

logs=[]
for path in sorted(RAW.glob('b17-*.log')):
    content=path.read_text(encoding='utf-8',errors='replace')
    logs.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                 'passes':len(re.findall(r'^PASS ',content,re.M)),
                 'issues':re.findall(r'^(?:FAIL |SCRIPT ERROR:|ERROR:|WARNING:).*',content,re.M)})
write('test-log-index.json',logs)

mapping={'b17-sources.json':'sources.json','b17-reward-matrix.json':'reward-matrix.json',
         'b14-growth-matrix-b17.json':'growth-matrix.json','b14-horde-b17-current.json':'horde.json',
         'b14-encounter-b17-current.json':'encounters.json','b17-bosses.json':'bosses.json','b17-boss-survival.json':'boss-survival.json'}
for source,dest in mapping.items():
    if (RAW/source).exists(): write(dest,read(source))

if (OUT/'sources.json').exists():
    rows=json.loads((OUT/'sources.json').read_text(encoding='utf-8'))['rows']
    lines=['# B17 三源登记与证据边界','',
           '72 项来自当前运行注册表。被动属性、真实发射和资源事件是不同证据；下表不把尚未覆盖的生命周期组合标成 PASS。', '',
           '|来源|ID|名称|购买上限|规则 / 条件|实现|', '|---|---|---|---|---|---|']
    for row in rows:
        definition=row.get('definition',{})
        name=row.get('name',definition.get('name',''))
        info=row.get('info',definition.get('info',str(definition)))
        lines.append('|'+ '|'.join(str(x).replace('|','/').replace('\n','；') for x in
                                  [row['kind'],row['id'],name,row['purchase_cap'],info,row['source']])+'|')
    lines += ['', '真实数据：独立 HP 与交易见 sources.json；原型直接事件见 reward-matrix.json；24 枪三源实发、资源与生命周期检查见 test-log-index.json。',
              '', '原生 depth=1 分支保留原型“直接命中/直接击杀”文案限制；强化和天赋的 native_attack 资格独立，不把 depth 归零。',
              '', 'saved 计算已隔离 live 基础字段、击杀层数和原型状态；B17Saved 使用真实校验/加载路径检验独立性和历史超限持有。旧 schema 未保存的 base_* 字段按历史默认零，不从当前角色推断。',
              '', '旧档超限计数保留；新购买以效果上限拒绝。概率/条件效果不作为常驻伤害相加；同组百分比相加，独立倍率相乘，暴击是百分点，射频、装填秒数和每 tick 伤害分别记录。']
    (ROOT/'docs/iteration/b17-sources.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

print('B17 summaries written; historical evidence untouched')
