"""Preserve previous fixtures and record every new run in the M7 evidence folder."""
from pathlib import Path
import json, re, subprocess, sys

root = Path(__file__).resolve().parents[1]
engine = root.parent/'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
outdir = root/'docs/iteration/evidence/m7'
if '--final' in sys.argv: outdir /= 'final-regression'
outdir.mkdir(parents=True,exist_ok=True)
cases = [(s, []) for s in ['BaselineRegression','ContractRunner']]
cases += [('SaveRunner',[mode]) for mode in ['write','read']]
cases += [(s,[]) for s in ['R1Regression','R1Persistence','R1Flow','R1RecoveryUI','R1LegacyRestore']]
cases += [('R1SaveMatrix',['write'])]
cases += [('R1SaveMatrix',['read',str(v),order]) for cycle in range(3) for v in range(3) for order in ['forward','reverse']]
cases += [('R1DepartureSave',[mode,variant]) for variant in ['normal','trial'] for mode in ['write','read']]
cases += [(s,[]) for s in ['M4ThermalClock','M3Weapons','M3Energy','M3Special','M4Mechanics','M4UI','M4Attachments','M4Talents']]
cases += [('M4Persistence',[]),('M4Persistence',['read']),('M4Combinations',[])]
cases += [(s,[]) for s in ['M5Enemies','M5World','M5Mechanics','M5BossCombat','M6Contracts','M6Cross','M6SaveUI']]
if '--final' in sys.argv: cases += [(s,[]) for s in ['M6Layout','M6BossStops','M7Shop','M7Migration','M7Contracts']]
results = []
reindex = '--reindex' in sys.argv
recorded = json.loads((outdir/'regression-index.json').read_text(encoding='utf-8')) if reindex else []
for index,(scene,args) in enumerate(cases):
    logpath = outdir/f'regression-{index:02}-{scene}.txt'
    if reindex:
        assert index < len(recorded) and recorded[index]['scene'] == scene and recorded[index]['args'] == args
        code = recorded[index]['code']
    else:
      with logpath.open('w',encoding='utf-8') as log:
        command = [str(engine),'--headless','--verbose','--max-fps','160','--path',str(root),'res://tests/'+scene+'.tscn']
        if args: command += ['--']+args
        try: code = subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600 if scene == "M7Contracts" else 240).returncode
        except subprocess.TimeoutExpired: code = -1
    text = logpath.read_text(encoding='utf-8')
    summaries = re.findall(r'(?:SUMMARY )?checks=(\d+) failures=(\d+)',text)
    if not summaries:
        legacy = re.findall(r'^[A-Z][A-Z0-9 _-]* failures=(\d+)$',text,re.M)
        if legacy: summaries = [(str(len(re.findall(r'^PASS ',text,re.M))),legacy[-1])]
    counts = summaries[-1] if summaries else ('0','1')
    leaked = re.findall(r'Leaked instance: (\w+):',text)
    # Classify the actual identities, never accept arbitrary "2 objects".
    audio_teardown = sorted(leaked) == ['AudioStreamMP3','AudioStreamPlaybackMP3'] and 'Resource still in use: res://audio/bgm/Cephalopod.mp3 (AudioStreamMP3)' in text
    errors = [line for line in text.splitlines() if 'ERROR:' in line and not (audio_teardown and line.startswith('ERROR: 1 resources still in use at exit'))]
    passed = code == 0 and bool(summaries) and int(counts[1]) == 0 and not errors and 'FAIL ' not in text and (not leaked or audio_teardown)
    row = dict(scene=scene,args=args,checks=int(counts[0]),failures=int(counts[1]),code=code,passed=passed,clean_exit=not leaked and not errors,audio_teardown=audio_teardown,log=logpath.name)
    results.append(row)
    print(json.dumps(row),flush=True)
    (outdir/'regression-index.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
