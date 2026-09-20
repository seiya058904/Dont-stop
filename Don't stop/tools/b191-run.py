"""Bounded B19.1 runner. Each invocation preserves exact command, exit and diagnostics."""
import sys,subprocess,json,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
engine=root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
label,*args=sys.argv[1:]
out=root/'output/b19-1';out.mkdir(parents=True,exist_ok=True)
log=out/(label+'.log')
if log.exists(): raise SystemExit('Refusing overwrite: '+str(log))
command=[str(engine),'--path',str(root),*args]
start=time.time()
try:
 with log.open('w',encoding='utf8') as f:
  result=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT,timeout=240)
 code=result.returncode
except subprocess.TimeoutExpired: code=124
text=log.read_text(encoding='utf8',errors='replace')
issues=[l for l in text.splitlines() if l.startswith(('SCRIPT ERROR','ERROR:','FAIL ','WARNING:'))]
data={'command':command,'exit':code,'seconds':time.time()-start,'passes':text.count('\nPASS '),'diagnostics':issues}
(out/(label+'.json')).write_text(json.dumps(data,indent=2),encoding='utf8')
print(label,json.dumps(data),flush=True)
raise SystemExit(code or int(any(l.startswith(('SCRIPT ERROR','FAIL ')) for l in issues)))
