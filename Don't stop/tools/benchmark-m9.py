"""Sequential native rendering, after all power fixtures have stopped."""
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[1]
out = root/'docs/iteration/evidence/m9'
dependencies = ['power-raw-v2','power-final-v1','crowd-raw-final','crowd-build-final']
deadline=time.monotonic()+1800
while not all((out/label/'execution.json').exists() for label in dependencies):
    if time.monotonic()>deadline:
        raise SystemExit('Power evidence is still incomplete; no performance samples taken.')
    time.sleep(5)
for scenario in ['normal','late','boss','projectile','telegraph','particle','boss-barrage']:
    result=subprocess.run([sys.executable,str(root/'tools/run-m9.py'),'perf-final-'+scenario,
                           'M9Perf','--render',scenario])
    if result.returncode:
        raise SystemExit(result.returncode)
