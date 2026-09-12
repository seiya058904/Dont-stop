"""Run one bounded fixture in an isolated process and retain OS/source evidence."""
import ctypes, hashlib, json, pathlib, subprocess, sys, time
root = pathlib.Path(__file__).resolve().parents[1]
engine = root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
name, scene, *args = sys.argv[1:]
evidence = root/'docs/iteration/evidence/m7'
paths = list((root/'autoload').rglob('*.gd'))+list((root/'game').rglob('*.gd'))+list((root/'ui').rglob('*.gd'))+[root/'tests'/f'{scene}.gd']
def hashes(): return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
before = hashes()
start = time.time()
with (evidence/f'{name}.txt').open('w',encoding='utf-8') as log:
    command = [str(engine),'--headless','--verbose','--max-fps','160','--path',str(root),f'res://tests/{scene}.tscn']
    if args: command += ['--']+args
    process = subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    (evidence/f'{name}-process.json').write_text(json.dumps(dict(pid=process.pid,command=command,started=start)),encoding='utf-8')
    try: code = process.wait(timeout=3600)
    except subprocess.TimeoutExpired: process.kill(); code = -1
after = hashes()
(evidence/f'{name}-execution.json').write_text(json.dumps(dict(seconds=time.time()-start,code=code,source_unchanged=before==after,before=before,after=after),indent=2),encoding='utf-8')
