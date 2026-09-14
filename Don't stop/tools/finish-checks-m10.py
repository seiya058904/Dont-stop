"""Run functional checks after native benchmarks have released the machine."""
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[1]
marker = root/'docs/iteration/evidence/m10/perf-final-particle/execution.json'
while not marker.exists():
    time.sleep(5)
cases = [
    ('interaction-final', 'M10Interaction', []),
    ('reward-matrix-final', 'M10RewardMatrix', []),
    ('growth-review', 'M10Growth', []),
    ('cross-review', 'M6Cross', []),
    ('special-review', 'M3Special', []),
    ('density-typical', 'M10Density', ['typical']),
    ('density-play-29-final', 'M10Density', ['only29']),
]
for label, scene, args in cases:
    code = subprocess.run([sys.executable, str(root/'tools/run-m10.py'), label, scene, *args]).returncode
    print(label, code, flush=True)
