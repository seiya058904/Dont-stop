"""Assemble M9 evidence; missing or failing evidence never becomes PASS."""
import ast
import csv
import json
import pathlib
import re
import statistics
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
out = root/'docs/iteration/evidence/m9'

def read(relative):
    path = out/relative
    return json.loads(path.read_text(encoding='utf-8')) if path.exists() else None

def log(label):
    path = out/label/'run.txt'
    return path.read_text(encoding='utf-8') if path.exists() else ''

def marker(label, prefix):
    rows = re.findall(r'^'+re.escape(prefix)+r' (\{.*\})$', log(label), re.M)
    return json.loads(rows[-1]) if rows else None

presentation = read('presentation-final-v1/m9/presentation.json') or []
raw = read('power-raw-v2/m9/power-raw.json') or []
final = read('power-final-v1/m9/power-final.json') or []
raw_crowd = read('crowd-raw-final/m9/power-raw.json') or []
final_crowd = read('crowd-build-final/m9/power-final.json') or []
catalog = (root/'game/config/WeaponCatalog.gd').read_text(encoding='utf-8')
tiers = ast.literal_eval(re.search(r'^const TIERS = (.*)$', catalog, re.M)[1])
prices = ast.literal_eval(re.search(r'^const PRICES = (.*)$', catalog, re.M)[1])
def original(path):
    return subprocess.check_output(['git','show','b2f8f48:'+root.name+'/'+path],cwd=root.parent).decode('utf-8')
def section(text,name):
    return re.search(r'const '+name+r' = (\{.*?^\})',text,re.M|re.S)[1]
content=(root/'game/config/M5Content.gd').read_text(encoding='utf-8')
old_content=original('game/config/M5Content.gd')
frozen_files=['autoload/Demo.gd','autoload/PlayerData.gd','game/config/DemoConfig.gd',
              'game/config/CampSnapshot.gd','game/guns/BaseGun.gd','ui/CampPanel.gd',
              'ui/MainUI.gd','ui/ControlUI.tscn']
contracts={path:(root/path).read_text(encoding='utf-8').replace('\r\n','\n')==original(path).replace('\r\n','\n') for path in frozen_files}
for name in ['ENEMIES','BOSSES','WALLS']:
    contracts[name+'_unchanged']=section(content,name)==section(old_content,name)
contracts['POWER_unchanged']=re.search(r'^const POWER = (.*)$',catalog,re.M)[1]==re.search(r'^const POWER = (.*)$',original('game/config/WeaponCatalog.gd'),re.M)[1]
contracts['content_counts']={'weapons':len(tiers),'enemies':len(re.findall(r'"E\d+":',section(content,'ENEMIES'))),
                             'bosses':len(re.findall(r'"B\d+":',section(content,'BOSSES'))),
                             'regions':len(re.findall(r'"R\d+":',section(content,'REGIONS'))),
                             'encounters':len(re.findall(r'^\t\t\d+:',content,re.M))}
contracts['counts_preserved']=contracts['content_counts']==dict(weapons=24,enemies=12,bosses=3,regions=6,encounters=30)
(out/'source-contracts.json').write_text(json.dumps(contracts,indent=2),encoding='utf-8')

def by_id(rows, scenario):
    return {row['id']: row for row in rows if row['scenario']==scenario}

rs, rb = by_id(raw,'single'), by_id(raw,'boss')
fs, fb = by_id(final,'single'), by_id(final,'boss')
rc, fc = by_id(raw_crowd,'crowd'), by_id(final_crowd,'crowd')
matrix = []
for weapon_id in sorted(tiers, key=lambda value: (tiers[value], prices[str(value)])):
    cases = [row for row in presentation if row['id']==weapon_id]
    screenshot = f'weapons-visual-final-v2/m8/m9-weapon-{weapon_id}.png'
    row = dict(id=weapon_id, name=cases[0].get('name','') if cases else '',
               tier=tiers[weapon_id], price=prices[str(weapon_id)],
               mechanism=cases[0].get('mechanism','') if cases else '',
               primary_path_limit=cases[0]['declared_path_limit'] if cases else None,
               observed_visible_max=max((r['observed_visible_max'] for r in cases),default=None),
               presentation_cases=len(cases), mismatches=sum(not r['consistent'] for r in cases),
               screenshot=screenshot, screenshot_exists=(out/screenshot).exists(),
               raw_dps=rs.get(weapon_id,{}).get('dps'), final_dps=fs.get(weapon_id,{}).get('dps'),
               raw_boss_dps=rb.get(weapon_id,{}).get('dps'), final_boss_dps=fb.get(weapon_id,{}).get('dps'),
               raw_clear_seconds=rc.get(weapon_id,{}).get('clear_seconds'),
               final_clear_seconds=fc.get(weapon_id,{}).get('clear_seconds'))
    row['status'] = 'PASS' if len(cases)==6 and row['mismatches']==0 and row['screenshot_exists'] else 'OPEN'
    row['range_note'] = 'Primary projectile/beam path; AoE radius and conditional secondary paths are separate.'
    if weapon_id==118:
        row['range_note'] = '640 px mother path + up to 640 px one-generation fragment path; M9Paths tests a target at 1220 and excludes 1330.'
    elif weapon_id==122:
        row['range_note'] = 'Outbound 0.55 s then visible return to player; M9Paths verifies separate outbound/return hits.'
    elif weapon_id==121:
        row['range_note'] = '81 px nominal flight + 64 px field radius, clipped by walls; physics tick discretization applies.'
    elif weapon_id in [114,119,120]:
        row['range_note'] = 'Projectile path plus on-impact AoE radius; explosion footprint is wall clipped.'
    matrix.append(row)
(out/'weapon-matrix.json').write_text(json.dumps(matrix,indent=2,ensure_ascii=False),encoding='utf-8')
with (out/'weapon-matrix.csv').open('w',encoding='utf-8-sig',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(matrix[0])); writer.writeheader(); writer.writerows(matrix)

bosses = []
for build in ['high','full']:
    bosses += read(f'bosses-{build}-v2/m9/r1-boss-{build}.json') or []
patterns = read('barrage-final-v2/m9/barrage-final.json') or []
regression = read('regression.json') or []
recheck = read('regression-10-R1LegacyRestore-recheck/execution.json')
for row in regression:
    if row['scene']=='R1LegacyRestore' and recheck:
        row['initial_execution']=row['execution']
        row['execution']='regression-10-R1LegacyRestore-recheck/execution.json'
        row['errors']=recheck['errors']
        row['checks']=len(re.findall(r'^PASS ',log('regression-10-R1LegacyRestore-recheck'),re.M))
        row['passed']=recheck['code']==0 and not recheck['errors'] and row['checks']==5
        row['resolved_harness_issue']='Immutable copy omitted the fixture temporary-save directory; no product save change.'

scenarios=['normal','late','boss','projectile','telegraph','particle','boss-barrage']
performance=[]
for scenario in scenarios:
    before=marker('perf-baseline-'+scenario,'M9 PERF')
    after=marker('perf-final-'+scenario,'M9 PERF')
    paired_samples=None
    if scenario=='projectile':
        before_labels=['perf-baseline-projectile','perf-confirm-baseline-projectile','perf-third-baseline-projectile']
        after_labels=['perf-final-projectile','perf-confirm-final-projectile','perf-third-final-projectile']
        before_samples=[marker(label,'M9 PERF') for label in before_labels]
        after_samples=[marker(label,'M9 PERF') for label in after_labels]
        if all(before_samples+after_samples):
            paired_samples=dict(baseline=before_samples,final=after_samples,baseline_labels=before_labels,final_labels=after_labels,
                                method='Three paired samples; median percentiles and worst observed max. No samples discarded.')
            before=dict(before); after=dict(after)
            for key in ['p50','p95','p99']:
                before[key]=statistics.median(row[key] for row in before_samples)
                after[key]=statistics.median(row[key] for row in after_samples)
            before['max']=max(row['max'] for row in before_samples)
            after['max']=max(row['max'] for row in after_samples)
    execution=read('perf-final-'+scenario+'/execution.json')
    reviewed=bool(before and after and execution and execution['code']==0 and not execution['errors'])
    if reviewed:
        reviewed=after['p95']<=max(before['p95']*1.2,before['p95']+2) and after['p99']<=max(before['p99']*1.25,before['p99']+3)
        reviewed=reviewed and after['draw_calls']>0
        if scenario=='telegraph': reviewed=reviewed and after['zones_peak']>=60
    baseline_execution=read('perf-baseline-'+scenario+'/execution.json')
    same_fixture=bool(baseline_execution and execution and baseline_execution['source']['tests/M9Perf.gd']==execution['source']['tests/M9Perf.gd'])
    reviewed=reviewed and same_fixture
    if scenario=='projectile':
        reviewed=reviewed and paired_samples is not None
        for label in before_labels+after_labels:
            sample_execution=read(label+'/execution.json')
            reviewed=reviewed and bool(sample_execution and sample_execution['code']==0 and not sample_execution['errors'] and sample_execution['source']['tests/M9Perf.gd']==execution['source']['tests/M9Perf.gd'])
    performance.append(dict(scenario=scenario,baseline=before,final=after,within_review_budget=reviewed,
                            identical_pressure_fixture=same_fixture,paired_samples=paired_samples))
tier_summary=[]
for tier in range(1,6):
    subset=[r for r in matrix if r['tier']==tier and r['final_dps'] is not None]
    tier_summary.append(dict(tier=tier,weapons=len(subset),mean_single_dps=statistics.mean(r['final_dps'] for r in subset) if subset else None))

gates={
    'frozen_contracts':all(value for key,value in contracts.items() if key!='content_counts'),
    'beam': 'M9_BEAM_CHECKS 312 FAILURES 0' in log('beam-final-camera'),
    'presentation':len(presentation)==144 and all(r['status']=='PASS' for r in matrix),
    'secondary_paths':'M9_PATHS checks=8 failures=0' in log('paths-final-v1'),
    'power':all(len(rows)==24 for rows in [rs,rb,fs,fb,rc,fc]) and all(r['clear_seconds']>=0 for r in raw_crowd+final_crowd),
    'barrage':'M9_BARRAGE checks=9 failures=0' in log('barrage-final-v2'),
    'bosses':len(bosses)==6 and all(r['clear'] and r['boss']['phase_two'] for r in bosses),
    'regions':'M9_REGIONS checks=27 failures=0' in log('regions-final-v3') and all((out/f'regions-final-v3/m8/m9-region-{stage}.png').exists() for stage in [1,6,11,16,21,26]),
    'catalog':'M9_CATALOG_CHECKS 50 FAILURES 0' in log('catalog-final-v2'),
    'regression':len(regression)==22 and all(r['passed'] for r in regression),
    'performance':all(r['within_review_budget'] for r in performance),
}
summary=dict(gates=gates,ready=all(gates.values()),human_accepted=False,bosses=bosses,
             patterns=patterns,regression=regression,performance=performance,tier_summary=tier_summary)
(out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(dict(gates=gates,tier_summary=tier_summary),ensure_ascii=False,indent=2))

lines=['# Weapon Presentation and Power Audit','',
       'All damage values come from actual firing, reloads and target health changes. Raw damage excludes POWER and critical hits. Final samples use a level-one, unupgraded build; live high/full Boss runs are separate.',
       '', 'The crowd fixture uses six 30-HP targets at x=40/60 and y=-14/0/14 relative to the reference muzzle area, within the shortest weapon reach. Earlier wider/censored crowds are superseded. Single/Boss-dummy windows last 15 seconds; burst/reload details remain in source JSON.', '',
       '| ID | Weapon | Tier | Price | Raw DPS | Final DPS | Raw crowd s | Final crowd s | Presentation |',
       '|---|---|---|---|---|---|---|---|---|']
def fmt(value): return f'{value:.2f}' if isinstance(value,(float,int)) else 'OPEN'
for r in matrix:
    lines.append(f"| {r['id']} | [{r['name']}]({r['screenshot']}) | {r['tier']} | {r['price']} | {fmt(r['raw_dps'])} | {fmt(r['final_dps'])} | {fmt(r['raw_clear_seconds'])} | {fmt(r['final_clear_seconds'])} | {r['status']} |")
lines += ['', '## Tier decisions', '',
          '- ID 0: I → II. Raw sustained output competes with Tier II single-target weapons.',
          '- ID 4: III → IV. Strong raw sustained fire; raise rating/price without reducing damage.',
          '- BoomBoi (6): III → IV. Long, continuous and easy-to-place finite beam provides safety value beyond its DPS.',
          '- Cone (115): III → IV. Excellent measured grouped-target clear, offset by short reach.',
          '- Prism (111): IV → V. High raw close-target output plus independently wall-clipped branches.',
          '- Within Tier I, the slower measured shotgun is now 60 gold and Baby is 90 gold; Uzi remains 120. This price-only adjustment follows the power measurements and does not change their damage results.',
          '- All other ratings were reviewed using the matrix. POWER multipliers are unchanged. Crowd, range, homing/control and exposure differences permit matchup reversals; tier is not a DPS-only ordering.',
          '', '## Range interpretation', '',
          'The CSV separates the primary path from observed visible extent. A projectile stopped by an enemy does not demonstrate its empty-space maximum. Explosion radii, fragments, homing turns and returning paths cannot be represented faithfully by one straight-line range value. M9Paths and retained M3/M4/M6 suites cover those conditional paths. Captures show real runtime primitives, not human aesthetic approval.']
(out/'WEAPON-AUDIT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
