"""Final sequential regression and normal-health three-tier Boss verification."""
import pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[1]
commands=[[sys.executable,str(root/'tools/verify-m8.py'),'--r1']]
for tier in ['middle','high','full']:
    commands.append([sys.executable,str(root/'tools/run-m8.py'),f'r1-bosses-{tier}','M8Bosses',tier,'--r1'])
for command in commands:
    result=subprocess.run(command)
    if result.returncode: sys.exit(result.returncode)
