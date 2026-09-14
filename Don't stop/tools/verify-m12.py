"""Retain the M11 core suite and add M12 UX, tutorial and lifecycle evidence."""
import json
import pathlib
import re
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[1]
out = root / 'docs/iteration/evidence/m12'
out.mkdir(parents=True, exist_ok=True)
(out/'summary.json').write_text(json.dumps(dict(automated_pass=False, state='running', os_mouse_verified=False)), encoding='utf-8')
prefix = 'm12-' + time.strftime('%Y%m%d-%H%M%S')
subprocess.run([sys.executable, str(root/'tools/test-snapshot-lifecycle.py')], check=True)
legacy_summary = root / 'docs/iteration/evidence/m11/regression.json'
if '--extras-only' not in sys.argv:
    prior = legacy_summary.read_bytes()
    try:
        subprocess.run([sys.executable, str(root/'tools/verify-m11.py'), prefix])
        (out/'core-regression.json').write_bytes(legacy_summary.read_bytes())
    finally:
        temporary = legacy_summary.with_suffix(".json.restore")
        temporary.write_bytes(prior)
        temporary.replace(legacy_summary)
core = json.loads((out/'core-regression.json').read_text(encoding='utf-8'))
rows = []
for scene in ['M11Clarity', 'M11SaveMigration', 'M11Navigation', 'M11Spawn',
              'M11HordeContracts', 'M12Lesson', 'M12UX', 'M12Native']:
    label = prefix+'-'+scene
    args = ['--render'] if scene in ['M11Clarity', 'M12UX', 'M12Native'] else []
    if scene == 'M12Native' and '--visible' in sys.argv:
        args = ['--visible']
    subprocess.run([sys.executable, str(root/'tools/run-m11.py'), label, scene, *args])
    folder = root/'docs/iteration/evidence/m11'/label
    execution = json.loads((folder/'execution.json').read_text(encoding='utf-8'))
    log = (folder/'run.txt').read_text(encoding='utf-8')
    checks = len(re.findall(r'^PASS ', log, re.M))
    leaked = re.findall(r'Leaked instance: (\w+):', log)
    # Same bookkeeping whitelist as verify-m11.py: the BGM stream is retained on
    # the Music bus and reported at teardown. Since v1.0.1 the scenes load
    # res://audio/bgm/Cephalopod.ogg, not the MP3 build this list used to name.
    known_audio_types = {'AudioStreamMP3', 'AudioStreamPlaybackMP3', 'OggPacketSequence',
                         'AudioStreamOggVorbis', 'OggPacketSequencePlayback',
                         'AudioStreamPlaybackOggVorbis'}
    known_audio = bool(leaked) and set(leaked) <= known_audio_types and (
        'Cephalopod.mp3' in log or 'Cephalopod.ogg' in log)
    errors = execution['errors']
    if known_audio:
        errors = [line for line in errors
                  if not re.match(r'ERROR: \d+ resources still in use at exit', line)]
    passed = execution['code'] == 0 and checks > 0 and not errors and (not leaked or known_audio) and not pathlib.Path(execution['snapshot']).exists()
    rows.append(dict(scene=scene, passed=passed, checks=checks, errors=errors, known_audio_teardown=known_audio,
                     execution='../m11/'+label+'/execution.json', snapshot_removed=not pathlib.Path(execution['snapshot']).exists()))
    (out/'ux-regression.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    print(json.dumps(rows[-1]), flush=True)
passed = len(core)==32 and all(r['passed'] for r in core+rows)
(out/'summary.json').write_text(json.dumps(dict(automated_pass=passed, state='complete',
    core_cases=len(core), core_checks=sum(r['checks'] for r in core), specialized_cases=len(rows),
    specialized_checks=sum(r['checks'] for r in rows), lifecycle_checks=4, os_mouse_verified=False,
    exit_gate_complete=False, H1_STATUS='FIFTH_FEEDBACK_ADDRESSED', HUMAN_ACCEPTED=False), indent=2), encoding='utf-8')
print('M12_AUTOMATED_PASS', passed, 'OS_MOUSE_VERIFIED', False)
sys.exit(0 if passed else 1)
