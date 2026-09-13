"""Final source/UI check after exclusive pressure measurements have completed."""
import pathlib
import subprocess
import sys
import time
root=pathlib.Path(__file__).resolve().parents[1]
while not (root/'docs/iteration/evidence/m11/native-final-B/execution.json').exists(): time.sleep(5)
raise SystemExit(subprocess.run([sys.executable,str(root/'tools/run-m11.py'),'clarity-source-final','M11Clarity','--render']).returncode)
