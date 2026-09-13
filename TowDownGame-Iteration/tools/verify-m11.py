"""Retained gameplay regressions plus M8-R1 warning contracts, isolated per case."""
import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'docs/iteration/evidence/m11'
cases = [(name, []) for name in [
    'BaselineRegression', 'M3Weapons', 'M3Energy', 'M3Special', 'M4ThermalClock',
    'M4Talents', 'M6Cross', 'M6BossStops', 'M6Contracts', 'R1RecoveryUI',
    'R1LegacyRestore', 'M8Mechanics', 'M8Contracts', 'M8UI', 'M8Supply',
    'M8R1Telegraphs']]
cases += [('M7ExitWallet', [mode]) for mode in ['camp', 'menu', 'combat', 'restore', 'window']]
cases += [('M7MainExit', [])]
cases += [(name, []) for name in ["M10Growth","M10RewardAudit","M10RewardMatrix","M10Interaction","M10Ultimate","M10Barrage"]]
cases += [("M10Bosses",[tier]) for tier in ["high","full"]]
cases += [("M10Density",[]),("M10Density",["probe"])]
rows = []
for i, (scene, args) in enumerate(cases):
    if scene == 'M8Contracts':
        args = ['--r1']
    prefix = sys.argv[1] if len(sys.argv)>1 else 'regression'
    label = f'{prefix}-{i:02}-{scene}'
    result = subprocess.run([sys.executable, str(root/'tools/run-m11.py'), label, scene, *args])
    log = (out/label/'run.txt').read_text(encoding='utf-8')
    checks = len(re.findall(r'^PASS ', log, re.M))
    if scene == 'M7MainExit' and 'MAIN EXIT CLICK DISPATCHED' in log:
        checks = 1
    execution = json.loads((out/label/'execution.json').read_text(encoding='utf-8'))
    leaked = re.findall(r'Leaked instance: (\w+):', log)
    known_audio = sorted(leaked) == ['AudioStreamMP3', 'AudioStreamPlaybackMP3'] and 'Cephalopod.mp3' in log
    errors = execution['errors']
    if known_audio:
        errors = [line for line in errors if not line.startswith('ERROR: 1 resources still in use at exit')]
    passed = execution['code'] == 0 and checks > 0 and not errors and (not leaked or known_audio)
    rows.append(dict(scene=scene, args=args, passed=passed, checks=checks, errors=errors,
                     known_audio_teardown=known_audio, execution=f'{label}/execution.json'))
    (out/'regression.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    print(json.dumps(rows[-1]), flush=True)
sys.exit(0 if all(row['passed'] for row in rows) else 1)
