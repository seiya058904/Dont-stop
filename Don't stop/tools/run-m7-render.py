"""Bounded native rendering fixture, minimized and offscreen; no desktop input."""
import pathlib,subprocess,sys,time,json
root=pathlib.Path(__file__).resolve().parents[1]
engine=root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
name,scene,*args=sys.argv[1:]
command=[str(engine),'--path',str(root),'--position','-10000,-10000','--resolution','1366x768','--minimized',f'res://tests/{scene}.tscn']
if args:command+=['--']+args
out=root/'docs/iteration/evidence/m7';start=time.time()
with (out/(name+'.txt')).open('w',encoding='utf-8') as log:
 try:code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW).returncode
 except subprocess.TimeoutExpired:code=-1
(out/(name+'-execution.json')).write_text(json.dumps({'code':code,'seconds':time.time()-start,'command':command},indent=2),encoding='utf-8')
