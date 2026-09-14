"""Isolated diagnostic after the paired benchmark: classify live nodes and visual cost."""
import pathlib,json,time,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'docs/iteration/evidence/m7'; copy=root/'evidence/m7-perf-project'
engine=root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
while True:
 try:
  if len(json.loads((out/'benchmark-index.json').read_text(encoding='utf-8')))==12: break
 except (FileNotFoundError,json.JSONDecodeError): pass
 time.sleep(10)
changed=subprocess.check_output(['git','diff','--name-only','6e3219c','--','TowDownGame-Iteration/autoload','TowDownGame-Iteration/game','TowDownGame-Iteration/ui'],cwd=root.parent,text=True).splitlines()
for n in changed:
 n=n.removeprefix('TowDownGame-Iteration/')
 if n.endswith('.gd'): (copy/n).write_bytes((root/n).read_bytes())
runner=(root/'tests/M5Pressure.gd').read_text(encoding='utf-8')
runner=runner.replace('func finish():','''func finish():
	var counts = {}; var scripts = {}; var queue = [get_tree().root]
	while not queue.is_empty():
		var node = queue.pop_back(); queue.append_array(node.get_children())
		counts[node.get_class()] = counts.get(node.get_class(),0)+1
		if node.get_script():
			var path = node.get_script().resource_path
			scripts[path] = scripts.get(path,0)+1
	print("NODE PROFILE ",JSON.stringify({"classes":counts,"scripts":scripts,"spawned":spawn_counter,"kills":Combat.kill_events}))''')
(copy/'tests/M5Pressure.gd').write_text(runner,encoding='utf-8')
for mode in ['visual-on','visual-off']:
 for n in ['game/bullets/Bullet.gd','game/monster/BaseMonster.gd','game/guns/BaseGun.gd']:
  text=(root/n).read_text(encoding='utf-8')
  if mode=='visual-off':
   if n.endswith('BaseGun.gd'): text=text.replace('tier_muzzle.pulse(tier)','pass # isolated diagnostic only')
   elif n.endswith('BaseMonster.gd'):
    baseline=subprocess.check_output(['git','show','6e3219c:TowDownGame-Iteration/'+n],cwd=root.parent,text=True,encoding='utf-8')
    text=text[:text.rfind('func _draw():')]+'func _draw():'+baseline.split('func _draw():')[-1]
   else: text=text[:text.rfind('func _draw():')]+'func _draw():\n\tpass\n'
  (copy/n).write_text(text,encoding='utf-8')
 with (out/f'profile-{mode}.txt').open('w',encoding='utf-8') as log:
  code=subprocess.run([str(engine),'--headless','--max-fps','160','--path',str(copy),'res://tests/M5Pressure.tscn'],stdout=log,stderr=subprocess.STDOUT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW).returncode
 print(mode,code,flush=True)
