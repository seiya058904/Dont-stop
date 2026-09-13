"""Sequential native M9/M10 comparison; never lowers either pressure fixture."""
import json
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'docs/iteration/evidence/m10'
if '--after-regression' in sys.argv:
    marker = out / 'regression-final-21-M7MainExit/execution.json'
    while not marker.exists():
        time.sleep(5)
rows = []
for scenario in ['normal', 'late', 'density', 'boss', 'boss-barrage', 'projectile', 'telegraph', 'particle']:
    for version in ['baseline', 'final']:
        label = f'perf-{version}-{scenario}'
        args = [sys.executable, str(root/'tools/run-m10.py'), label, 'M10Perf', '--render', scenario]
        if version == 'baseline':
            args.append('--baseline')
        code = subprocess.run(args).returncode
        execution = json.loads((out/label/'execution.json').read_text(encoding='utf-8'))
        result = out/label/'m10/perf.json'
        rows.append({'label': label, 'runner_code': code, 'errors': execution['errors'],
                     'metrics': json.loads(result.read_text(encoding='utf-8')) if result.exists() else None})
        (out/'performance.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
        print(label, code, flush=True)
sys.exit(0 if all(row['runner_code'] == 0 for row in rows) else 1)
