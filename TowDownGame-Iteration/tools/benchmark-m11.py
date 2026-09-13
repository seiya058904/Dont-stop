"""Sequential active-fire build comparison; native runs never overlap one another."""
import pathlib
import subprocess
import sys
root=pathlib.Path(__file__).resolve().parents[1]
prefix=sys.argv[1]
args=sys.argv[2:]
failed=False
for build in ['B','A','C']:
    code=subprocess.run([sys.executable,str(root/'tools/run-m11.py'),prefix+'-'+build,'M11Horde',build,*args]).returncode
    print(prefix,build,code,flush=True)
    failed=failed or code!=0
raise SystemExit(1 if failed else 0)
