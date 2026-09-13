"""Isolated, bounded Godot evidence runner; never sends desktop input."""
import hashlib, json, pathlib, re, subprocess, sys, time
import importlib.util, shutil

root = pathlib.Path(__file__).resolve().parents[1]
engine = root.parent / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
name, scene, *args = sys.argv[1:]
if '--baseline' in args or '--pre-r1' in args:
    import shutil
    flag = '--baseline' if '--baseline' in args else '--pre-r1'
    args.remove(flag)
    baseline = root.parent/('archive/workspace-support/m8-baseline/TowDownGame-Iteration' if flag=='--baseline' else 'archive/workspace-support/m8-r1-baseline/TowDownGame-Iteration')
    for path in (root/'tests').glob('M8*'):
        shutil.copy2(path,baseline/'tests'/path.name)
    root = baseline
render = '--render' in args
if render: args.remove('--render')
out = root / 'docs/iteration/evidence/m8'
out.mkdir(parents=True, exist_ok=True)
measured_root=root
canonical_source={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['game','autoload','ui'] for p in (root/folder).rglob('*') if p.suffix in ['.gd','.tscn']}
render_substitutions=[]
if render:
    spec=importlib.util.spec_from_file_location('render_isolation',pathlib.Path(__file__).with_name('render-isolation.py'))
    isolation=importlib.util.module_from_spec(spec); spec.loader.exec_module(isolation)
    root,render_substitutions=isolation.prepare(root)
    (root/'docs/iteration/evidence/m8').mkdir(parents=True,exist_ok=True)
paths = [p for folder in ['autoload', 'game', 'ui'] for p in (root/folder).rglob('*') if p.suffix in ['.gd','.tscn']]
paths += [root/'project.godot']
paths += list((root/'tests').glob('M8*.gd'))
def hashes(): return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
before = hashes()
command = [str(engine), '--path', str(root), '--verbose', '--max-fps', '160']
command += ['--rendering-method','gl_compatibility','--position', '-10000,-10000', '--resolution', '1366x768', '--minimized'] if render else ['--headless']
command += [f'res://tests/{scene}.tscn']
if args: command += ['--'] + args
start = time.time()
with (out/f'{name}.txt').open('w', encoding='utf-8') as log:
    startup=subprocess.STARTUPINFO(); startup.dwFlags=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=7 # SW_SHOWMINNOACTIVE
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW,startupinfo=startup)
    try: code = process.wait(timeout=3600)
    except subprocess.TimeoutExpired: process.kill(); process.wait(); code = -1
text = (out/f'{name}.txt').read_text(encoding='utf-8')
errors = [s for s in text.splitlines() if 'ERROR:' in s or s.startswith('FAIL ')]
after = hashes()
changed = [path for path in before if before[path]!=after.get(path)]
record = dict(code=code, seconds=time.time()-start, command=command, source_unchanged=not changed, product_unchanged=not any(not path.startswith('tests/') for path in changed), changed_during_run=changed, source=before, errors=errors)
record['render_input_isolation']=render_substitutions
record['measured_root']=str(measured_root)
record['canonical_source']=canonical_source
if render:
    for path in (root/'docs/iteration/evidence/m8').iterdir():
        if path.is_file() and path.stat().st_mtime>=start: shutil.copy2(path,out/path.name)
(out/f'{name}-execution.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in record.items() if k not in ['source','canonical_source','command','render_input_isolation']}), flush=True)
sys.exit(0 if code == 0 and not errors else 1)
