"""Run one isolated Godot fixture and reject engine errors even with exit 0.

Usage: python tools/b14-run-native.py SCENE TAG [--render] [-- ARGUMENTS...]
The scene must use Demo.test_mode. Does not edit real saves or kill other runs.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument('scene')
p.add_argument('tag')
p.add_argument('--render', action='store_true')
left, extra = p.parse_known_args()
if not re.fullmatch(r'[A-Za-z0-9_-]+', left.scene + left.tag):
    p.error('scene/tag must be simple names')
root = Path(__file__).resolve().parents[1]
engine = root.parent / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
log = root / 'evidence/visual-upgrade-20260919' / (left.tag + '.log')
if log.exists():
    p.error(f'refusing to overwrite evidence: {log}')
args = [str(engine), '--path', str(root), f'res://tests/{left.scene}.tscn', '--log-file', str(log)]
if not left.render:
    args.append('--headless')
else:
    # Native rendering stays enabled; fixtures themselves make the window unfocusable.
    args += ['--position', '0,0']
if extra:
    args += ['--'] + (extra[1:] if extra[0] == '--' else extra)
result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)
content = log.read_text(encoding='utf-8', errors='replace') if log.exists() else 'ERROR: missing log'
errors = [line for line in content.splitlines() if re.match(r'^(FAIL |SCRIPT ERROR|ERROR:)', line)]
passes = sum(line.startswith('PASS ') for line in content.splitlines())
print(f'{left.scene}: exit={result.returncode}, checks={passes}, errors={len(errors)}, log={log.name}')
for line in errors[:20]:
    print(line)
sys.exit(1 if result.returncode or errors else 0)
