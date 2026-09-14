"""Wait for functional runs, then record exclusive native measurements."""
import pathlib
import subprocess
import sys
import time
root=pathlib.Path(__file__).resolve().parents[1]
evidence=root/'docs/iteration/evidence/m11'
for label in ['horde-final-C','regression-31-M10Density']:
    while not (evidence/label/'execution.json').exists(): time.sleep(5)
cases=[('clarity-review','M11Clarity',[]),('legacy-visual','M10Visual',[])]
cases += [('legacy-perf-'+scenario,'M10Perf',[scenario]) for scenario in ['normal','late','density','boss','boss-barrage','projectile','telegraph','particle']]
cases += [('native-baseline-C','M11Horde',['C','--baseline']),('native-final-C','M11Horde',['C']),('native-final-B','M11Horde',['B'])]
failed=False
for label,scene,args in cases:
    code=subprocess.run([sys.executable,str(root/'tools/run-m11.py'),label,scene,*args,'--render']).returncode
    print(label,code,flush=True)
    failed=failed or code!=0
raise SystemExit(1 if failed else 0)
