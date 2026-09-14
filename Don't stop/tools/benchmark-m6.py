"""Alternating M5/M6 uninstrumented runs in the isolated profile project.

All pressure inputs and percentile calculations remain the original M5 fixture.
Normal is a separate 48-second fixture, compared only against its own M5 run.
Do not combine these results with the instrumented attribution timings.
"""
from pathlib import Path
import hashlib, json, subprocess, os, shutil, sys
root = Path(__file__).resolve().parents[1]
copy = root/'evidence/m6-profile-project'
engine = root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
evidence = root/'docs/iteration/evidence/m6'
label = 'benchmark' if len(sys.argv)<2 else 'benchmark-'+sys.argv[1]
if not copy.exists():
    def copy_asset(source,destination):
        path = Path(source)
        if path.suffix in ['.gd','.tscn','.tres','.godot','.cfg','.py','.ps1'] or ('.godot' in path.parts and 'imported' not in path.parts):
            return shutil.copy2(source,destination)
        try: os.link(source,destination)
        except OSError: shutil.copy2(source,destination)
        return destination
    shutil.copytree(root,copy,copy_function=copy_asset,ignore=shutil.ignore_patterns('evidence','docs','shader_cache','editor','__pycache__','*.log'))
    (copy/'docs/iteration/evidence/m6').mkdir(parents=True)
changed = ['autoload/Combat.gd','game/monster/BaseMonster.gd']
versions = {'M5':{},'M6':{p:(root/p).read_bytes() for p in changed}}
for p in changed:
    versions['M5'][p] = subprocess.check_output(['git','show','62a49eaea7db3c960530ed215767728e6782fa21:TowDownGame-Iteration/'+p],cwd=root.parent)
runner = (root/'tests/M5Pressure.gd').read_text(encoding='utf-8')
assert 'var normal = false' in runner
(copy/'tests/M5Pressure.gd').write_text(runner.replace('var normal = false','var normal = "normal" in OS.get_cmdline_user_args()'),encoding='utf-8')
results = []
for i,(version,scenario) in enumerate([(v,'pressure') for v in ['M5','M6','M6','M5','M5','M6']]+[('M5','normal'),('M6','normal')]):
    for p,data in versions[version].items(): (copy/p).write_bytes(data)
    logpath = evidence/f'{label}-{i}-{version}-{scenario}.txt'
    command = [str(engine),'--headless','--max-fps','160','--path',str(copy),'res://tests/M5Pressure.tscn']
    if scenario == 'normal': command += ['--','normal']
    with logpath.open('w',encoding='utf-8') as log:
        code = subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW).returncode
    text = logpath.read_text(encoding='utf-8')
    line = next((s for s in text.splitlines() if s.startswith('PRESSURE {')),None)
    row = dict(version=version,scenario=scenario,code=code,log=logpath.name,metrics=json.loads(line[9:]) if line else None,source={p:hashlib.sha256(data).hexdigest() for p,data in versions[version].items()})
    results.append(row)
    (evidence/f'{label}-index.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(version,scenario,row['metrics']['frame_ms'] if line else 'FAILED',flush=True)
