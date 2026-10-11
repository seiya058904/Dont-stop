"""Run real engine processes against a caller-provided isolated candidate.

The imported candidate must contain tests/R1CrossProcessRecovery.tscn. Outputs
and user data are retained; the runner neither imports nor deletes anything.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

CANONICAL = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    out = args.out.resolve()
    if project == CANONICAL or not (project/'tests/R1CrossProcessRecovery.tscn').is_file():
        parser.error('--project must be a separate imported candidate with the regression scene')
    if out == CANONICAL or out.is_relative_to(CANONICAL):
        parser.error('--out must be outside the canonical project')
    engine = str(Path(args.godot).resolve()) if Path(args.godot).exists() else args.godot
    version = subprocess.check_output([engine,'--version'],text=True,encoding='utf-8').strip()
    if not version.startswith('4.7.2.stable.'):
        parser.error('--godot must be Godot 4.7.2 stable')
    out.mkdir(parents=True,exist_ok=False)
    userdata = out/'userdata'; userdata.mkdir()
    temporary = out/'temp'; temporary.mkdir()
    env = dict(os.environ,APPDATA=str(userdata),LOCALAPPDATA=str(userdata),XDG_DATA_HOME=str(userdata),XDG_CONFIG_HOME=str(userdata/'config'),TEMP=str(temporary),TMP=str(temporary))
    results = []
    for stage, minimum in [('before',5),('after',34),('verify-archives',6)]:
        command = [engine,'--headless','--path',str(project),'--log-file',str(out/(stage+'.godot.log')),'res://tests/R1CrossProcessRecovery.tscn','--',stage]
        started = time.perf_counter()
        try:
            completed = subprocess.run(command,cwd=project,env=env,capture_output=True,timeout=120)
            code = completed.returncode
            text = completed.stdout.decode('utf-8','replace')+'\n'+completed.stderr.decode('utf-8','replace')
        except subprocess.TimeoutExpired as error:
            code = 124
            text = (error.stdout or b'').decode('utf-8','replace')+'\n'+(error.stderr or b'').decode('utf-8','replace')
        (out/(stage+'.log')).write_text(text,encoding='utf-8')
        success = code == 0 and len(re.findall(r'^PASS ',text,re.M)) >= minimum and not re.search(r'^(?:FAIL |SCRIPT ERROR)',text,re.M) and bool(re.search(r'R1 CROSS PROCESS '+stage+r' checks=\d+ failures=0',text))
        results.append(dict(stage=stage,command=command,exit=code,seconds=round(time.perf_counter()-started,3),success=success))
        if not success: break
    successful = len(results) == 3 and all(r['success'] for r in results)
    (out/'results.json').write_text(json.dumps(dict(results=results,success=successful,engine_version=version,userdata=str(userdata),retained=True),indent=2),encoding='utf-8')
    print(json.dumps(dict(success=successful,results=results),indent=2))
    return 0 if successful else 1

if __name__ == '__main__':
    raise SystemExit(main())
