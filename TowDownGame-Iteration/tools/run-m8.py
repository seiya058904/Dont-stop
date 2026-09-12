"""Isolated, bounded Godot evidence runner; never sends desktop input."""
import hashlib, json, pathlib, re, subprocess, sys, time

root = pathlib.Path(__file__).resolve().parents[1]
engine = root.parent / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
name, scene, *args = sys.argv[1:]
if '--baseline' in args:
    import shutil
    args.remove('--baseline')
    baseline = root.parent/'archive/workspace-support/m8-baseline/TowDownGame-Iteration'
    for path in (root/'tests').glob('M8*'):
        shutil.copy2(path,baseline/'tests'/path.name)
    root = baseline
render = '--render' in args
if render: args.remove('--render')
out = root / 'docs/iteration/evidence/m8'
out.mkdir(parents=True, exist_ok=True)
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
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    try: code = process.wait(timeout=3600)
    except subprocess.TimeoutExpired: process.kill(); process.wait(); code = -1
text = (out/f'{name}.txt').read_text(encoding='utf-8')
errors = [s for s in text.splitlines() if 'ERROR:' in s or s.startswith('FAIL ')]
after = hashes()
changed = [path for path in before if before[path]!=after.get(path)]
record = dict(code=code, seconds=time.time()-start, command=command, source_unchanged=not changed, product_unchanged=not any(not path.startswith('tests/') for path in changed), changed_during_run=changed, source=before, errors=errors)
(out/f'{name}-execution.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in record.items() if k not in ['source','command']}), flush=True)
sys.exit(0 if code == 0 and not errors else 1)
