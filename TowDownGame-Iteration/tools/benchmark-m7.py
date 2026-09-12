"""Alternating M6/M7 on identical pressure input; isolated source copies only."""
from pathlib import Path
import hashlib,json,subprocess,os,shutil,time,sys
root=Path(__file__).resolve().parents[1]
copy=root/'evidence/m7-perf-project'
out=root/'docs/iteration/evidence/m7'
engine=root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
if not copy.exists():
 def asset(source,destination):
  path=Path(source)
  if path.suffix in ['.gd','.tscn','.tres','.godot','.cfg','.py','.ps1'] or ('.godot' in path.parts and 'imported' not in path.parts):return shutil.copy2(source,destination)
  try:os.link(source,destination)
  except OSError:shutil.copy2(source,destination)
  return destination
 shutil.copytree(root,copy,copy_function=asset,ignore=shutil.ignore_patterns('evidence','docs','shader_cache','editor','__pycache__','*.log'))
changed=subprocess.check_output(['git','diff','--name-only','6e3219c','--','TowDownGame-Iteration/autoload','TowDownGame-Iteration/game','TowDownGame-Iteration/ui'],cwd=root.parent,text=True).splitlines()
changed=[n.removeprefix('TowDownGame-Iteration/') for n in changed if n.endswith('.gd')]
versions={'M7':{n:(root/n).read_bytes() for n in changed},'M6':{}}
for n in changed:
 baseline=subprocess.run(['git','show','6e3219c:TowDownGame-Iteration/'+n],cwd=root.parent,capture_output=True)
 # New M7-only effects are inert under M6 BaseGun; keep the file to allow cached imports.
 versions['M6'][n]=baseline.stdout if baseline.returncode==0 else versions['M7'][n]
runner=(root/'tests/M5Pressure.gd').read_text(encoding='utf-8')
runner=runner.replace('var normal = false','var normal = "normal" in OS.get_cmdline_user_args()').replace('if DisplayServer.get_name() != "headless": get_tree().quit(2); return','# Both headless and offscreen render use the identical fixture.')
# Wait until the authorized encounter audit stops competing for CPU/GPU samples.
start=time.time()
def regression_done():
 f=out/'final-regression/regression-index.json'
 if not f.exists(): return False
 try: rows=json.loads(f.read_text(encoding='utf-8')); return len(rows)==55
 except json.JSONDecodeError: return False
while not (regression_done() and all((out/f'audit-{t}-execution.json').exists() for t in ['basic','middle','late'])):
 if time.time()-start>3000:raise RuntimeError('Audit wait timed out')
 time.sleep(10)
if '--optimized' in sys.argv:
 out=out/'optimized-performance'; out.mkdir(exist_ok=True)
results=[]
cases=[(v,'pressure','headless') for v in ['M6','M7','M7','M6','M6','M7']]+[(v,'normal','headless') for v in ['M6','M7']]+[(v,'tier5','gpu') for v in ['M6','M7','M7','M6']]
for i,(version,scenario,display) in enumerate(cases):
 for n,data in versions[version].items():(copy/n).write_bytes(data)
 text=runner
 if scenario=='tier5':
  text=text.replace('var main\n','var main\nvar render_view\n').replace('\tadd_child(main)','\trender_view = SubViewport.new(); render_view.size = Vector2i(1366,768); render_view.world_2d = get_viewport().world_2d; render_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(render_view); render_view.add_child(main)')
  text=text.replace('[117,118,120,121,122,116]','[117,118,120,121,122,116,113,119,124]').replace('special_index%6','special_index%9')
  text=text.replace('func finish():','func finish():\n\tprint("RENDER DRAW CALLS ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))')
 (copy/'tests/M5Pressure.gd').write_text(text,encoding='utf-8')
 path=out/f'benchmark-{i:02}-{version}-{scenario}-{display}.txt'
 command=[str(engine),'--max-fps','160','--path',str(copy)]
 if display=='headless':command+=['--headless']
 else:command+=['--rendering-method','gl_compatibility','--position','-10000,-10000','--resolution','1366x768','--minimized']
 command+=['res://tests/M5Pressure.tscn']
 if scenario=='normal':command+=['--','normal']
 with path.open('w',encoding='utf-8') as log:
  try:code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW).returncode
  except subprocess.TimeoutExpired:code=-1
 text=path.read_text(encoding='utf-8');line=next((l for l in text.splitlines() if l.startswith('PRESSURE {')),None)
 row={'version':version,'scenario':scenario,'display':display,'code':code,'log':path.name,'metrics':json.loads(line[9:]) if line else None,'source':{n:hashlib.sha256(b).hexdigest() for n,b in versions[version].items()}}
 results.append(row);(out/'benchmark-index.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print(version,scenario,display,code,row['metrics']['frame_ms'] if line else 'NO RESULT',flush=True)
