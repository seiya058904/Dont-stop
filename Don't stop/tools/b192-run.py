"""Bounded native/release runner with low-frequency, exact-process RSS samples."""
import json
import hashlib
import subprocess
import sys
import time
from pathlib import Path

import psutil

root = Path(__file__).resolve().parents[1]
platform, label, *args = sys.argv[1:]
out = root / 'output/b19-2'
out.mkdir(parents=True, exist_ok=True)
log = out / (label + '.log')
if log.exists():
    raise SystemExit('Refusing overwrite: ' + str(log))
engine = (root.parent / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
          if platform == 'native' else root / 'build/b192-windows/Dont-stop.exe')
command = [str(engine), *( ['--path', str(root)] if platform == 'native' else [] ), *args]
identity = {'exe_sha256': hashlib.sha256(engine.read_bytes()).hexdigest()}
if platform == 'windows':
    # Release templates reject path overrides. The adjacent same-stem PCK is
    # the product's normal launch path, with its identity verified before launch.
    identity['pck_sha256'] = hashlib.sha256(engine.with_suffix('.pck').read_bytes()).hexdigest()
started = time.monotonic()
memory = []
with log.open('w', encoding='utf8') as stream:
    process = subprocess.Popen(command, cwd=engine.parent if platform == 'windows' else root, stdout=stream, stderr=subprocess.STDOUT)
    observed = psutil.Process(process.pid)
    while process.poll() is None:
        try:
            info = observed.memory_info()
            memory.append({'wall_s': time.monotonic()-started, 'pid': process.pid,
                           'rss': info.rss, 'private': getattr(info, 'private', None)})
        except psutil.NoSuchProcess:
            break
        if time.monotonic()-started > 240:
            process.kill()
            break
        time.sleep(2)
    code = process.wait()
lines = log.read_text(encoding='utf8', errors='replace').splitlines()
data = {'command': command, 'identity': identity, 'pid': process.pid, 'exit': code,
        'wall_s': time.monotonic()-started, 'process_memory': memory,
        'diagnostics': [line for line in lines if line.startswith(('ERROR:', 'SCRIPT ERROR:', 'WARNING:', 'FAIL '))]}
for prefix, key in [('[stress-frames] ', 'raw_frames'), ('[stress-convergence] ', 'convergence'),
                    ('[stress-boss] ', 'boss')]:
    matches = [line[len(prefix):] for line in lines if line.startswith(prefix)]
    if matches:
        data[key] = json.loads(matches[-1])
(out / (label + '.json')).write_text(json.dumps(data, indent=2), encoding='utf8')
print(json.dumps({key: value for key, value in data.items() if key not in ('raw_frames','boss','process_memory')}, ensure_ascii=False))
raise SystemExit(code or int(any(line.startswith(('ERROR:', 'SCRIPT ERROR:', 'FAIL ')) for line in data['diagnostics'])))
