"""Relevant retained contracts plus explicit replacements for the retired instance model."""
import hashlib, json, pathlib, re, subprocess, sys, time
root=pathlib.Path(__file__).resolve().parents[1]
engine=root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64.exe'
out=root/('docs/iteration/evidence/m8/r1-regression' if '--r1' in sys.argv else 'docs/iteration/evidence/m8/regression'); out.mkdir(exist_ok=True)
cases=[(name,[]) for name in ['BaselineRegression','M3Weapons','M3Energy','M3Special','M4ThermalClock','M4Talents','M6Cross','M6BossStops','M6Contracts','R1RecoveryUI','R1LegacyRestore','M8Mechanics','M8Contracts','M8UI','M8Supply']]
cases += [('M7ExitWallet',[mode]) for mode in ['camp','menu','combat','restore','window']]
cases += [('M7MainExit',[])]
if '--r1' in sys.argv: cases=[(scene,['--r1'] if scene=='M8Contracts' else args) for scene,args in cases]
def hashes():
    return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['game','autoload','ui'] for p in (root/folder).rglob('*') if p.suffix in ['.gd','.tscn']}
before=hashes()
results=[]
for i,(scene,args) in enumerate(cases):
    path=out/f'{i:02}-{scene}.txt'
    command=[str(engine),'--headless','--verbose','--max-fps','160','--path',str(root),f'res://tests/{scene}.tscn']
    if args: command+=['--']+args
    started=time.time()
    with path.open('w',encoding='utf-8') as log:
        try: code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300,creationflags=subprocess.CREATE_NO_WINDOW).returncode
        except subprocess.TimeoutExpired: code=-1
    content=path.read_text(encoding='utf-8')
    errors=[line for line in content.splitlines() if 'ERROR:' in line or line.startswith('FAIL ')]
    # Keep the previously identified audio teardown separate from runtime correctness.
    leaked=re.findall(r'Leaked instance: (\w+):',content)
    known_audio=sorted(leaked)==['AudioStreamMP3','AudioStreamPlaybackMP3'] and 'Cephalopod.mp3' in content
    if known_audio: errors=[line for line in errors if not line.startswith('ERROR: 1 resources still in use at exit')]
    count=len(re.findall(r'^PASS ',content,re.M))
    if scene=='M7MainExit' and code==0 and 'MAIN EXIT CLICK DISPATCHED' in content: count=1
    row=dict(scene=scene,args=args,code=code,checks=count,seconds=time.time()-started,errors=errors,known_audio_teardown=known_audio,passed=code==0 and count>0 and not errors and (not leaked or known_audio))
    results.append(row); (out/'index.json').write_text(json.dumps(results,indent=2),encoding='utf-8'); print(json.dumps(row),flush=True)
(out/'source.json').write_text(json.dumps(dict(source=before,product_unchanged=before==hashes()),indent=2),encoding='utf-8')
sys.exit(0 if all(r['passed'] for r in results) else 1)
