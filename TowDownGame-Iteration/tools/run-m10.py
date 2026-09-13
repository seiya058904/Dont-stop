"""Run an immutable M9 snapshot, preserving source hashes and native evidence."""
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
sys.dont_write_bytecode = True
from snapshot_lifecycle import allocate, git_baseline, remove_owned_tree

root = pathlib.Path(__file__).resolve().parents[1]
label, scene, *args = sys.argv[1:]
if not re.fullmatch(r'[a-zA-Z0-9_-]+', label):
    raise SystemExit('Use a simple evidence label')
render = '--render' in args
if render:
    args.remove('--render')
support = root.parent / 'archive/workspace-support'
out = root / 'docs/iteration/evidence/m10' / label
if out.exists():
    raise SystemExit('Evidence label already exists; use a new label')
run_root = allocate(support, 'm10', label)
source_root = root
baseline_revision = None
if '--baseline' in args:
    args.remove('--baseline')
    baseline_revision = '3946250'
    source_root = git_baseline(root, run_root / 'baseline', baseline_revision)
snapshot = run_root / root.name

def copy_asset(src, dst):
    if pathlib.Path(src).suffix.lower() in ['.png', '.jpg', '.ogg', '.mp3', '.wav', '.ctex', '.ttf', '.otf']:
        try:
            os.link(src, dst)
            return dst
        except OSError:
            pass
    return shutil.copy2(src, dst)

shutil.copytree(source_root, snapshot, copy_function=copy_asset,
                ignore=shutil.ignore_patterns('evidence', 'docs', 'shader_cache', 'editor', '__pycache__', '*.log'))
# Baseline gets the exact same new pressure fixture, never new product code.
if source_root != root:
    for fixture in (root / 'tests').glob('M10*'):
        shutil.copy2(fixture, snapshot / 'tests' / fixture.name)
source = {p.relative_to(snapshot).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for folder in ['game', 'autoload', 'ui', 'tests']
          for p in (snapshot / folder).rglob('*') if p.suffix in ['.gd', '.tscn', '.gdshader']}
substitutions = []
if render:
    for path in snapshot.rglob('*'):
        if '.godot' in path.parts or path.suffix not in ['.gd', '.tscn', '.tres']:
            continue
        content = path.read_text(encoding='utf-8-sig')
        updated = re.sub(r'Input\.mouse_mode\s*=\s*Input\.MOUSE_MODE_(?:CONFINED_HIDDEN|CONFINED|CAPTURED|HIDDEN)', 'Input.mouse_mode = Input.MOUSE_MODE_VISIBLE', content)
        updated = re.sub(r'(?m)^(\s*)(?:get_viewport\(\)|Input)\.warp_mouse\([^\n]*\)', r'\1pass # render-only input isolation', updated)
        if updated != content:
            path.write_text(updated, encoding='utf-8')
            substitutions.append(path.relative_to(snapshot).as_posix())
for milestone in ['m12', 'm11', 'm8', 'm9', 'm10']:
    (snapshot / 'docs/iteration/evidence' / milestone).mkdir(parents=True, exist_ok=True)
# This retained fixture writes a temporary res:// save and assumes its directory
# already exists in the original checkout. Snapshotting intentionally omits old saves.
if scene == 'R1LegacyRestore':
    (snapshot / 'evidence/r1-save').mkdir(parents=True, exist_ok=True)
out.mkdir(parents=True)
engine = support / '_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
command = [str(engine), '--path', str(snapshot), '--verbose', '--max-fps', '160']
command += ['--rendering-method', 'gl_compatibility', '--position', '-10000,-10000', '--resolution', '1366x768', '--minimized'] if render else ['--headless']
command += [f'res://tests/{scene}.tscn']
if args:
    command += ['--'] + args
started = time.time()
startup = subprocess.STARTUPINFO()
startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 7
with (out / 'run.txt').open('w', encoding='utf-8') as log:
    try:
        code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=3600,
                              startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW).returncode
    except subprocess.TimeoutExpired:
        code = -1
content = (out / 'run.txt').read_text(encoding='utf-8')
errors = [line for line in content.splitlines() if 'ERROR:' in line or line.startswith('FAIL ')]
for path in (snapshot / 'docs/iteration/evidence').rglob('*'):
    if path.is_file():
        destination = out / path.relative_to(snapshot / 'docs/iteration/evidence')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
remove_owned_tree(run_root, support / "test-temp")
record = dict(snapshot_retained=False, baseline_revision=baseline_revision, code=code, seconds=time.time()-started, errors=errors, source=source,
              snapshot=str(snapshot), command=command, render_input_substitutions=substitutions)
(out / 'execution.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
print(json.dumps({k: v for k, v in record.items() if k not in ['source', 'command']}), flush=True)
sys.exit(0 if code == 0 and not errors else 1)
