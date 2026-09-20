"""Bounded local Godot runner; preserves logs and rejects script errors."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
engine = root.parent / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
label, *args = sys.argv[1:]
out = root / 'evidence/b18'
out.mkdir(parents=True, exist_ok=True)
log = out / (label + '.log')
if log.exists():
    raise SystemExit('Refusing to overwrite ' + str(log))
with log.open('w', encoding='utf-8') as stream:
    result = subprocess.run([str(engine), '--path', str(root), *args], stdout=stream,
                            stderr=subprocess.STDOUT, timeout=900)
text = log.read_text(encoding='utf-8', errors='replace')
errors = [line for line in text.splitlines() if line.startswith(('SCRIPT ERROR', 'ERROR:', 'FAIL '))]
print(label, 'exit', result.returncode, 'errors', len(errors), 'passes', text.count('\nPASS '))
for line in errors[:20]:
    print(line)
raise SystemExit(1 if result.returncode or errors else 0)
