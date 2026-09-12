"""Instrument synchronous GDScript functions, run unchanged M5 pressure, restore bytes.

Do not run alongside other Godot processes using this checkout. Timings include
instrumentation overhead; compare uninstrumented pressure separately. Nested
scopes report inclusive and exclusive time, never sum inclusive totals.
"""
import pathlib, re, subprocess, sys

root = pathlib.Path(__file__).resolve().parents[1]
engine = root.parent / 'archive/workspace-support/_tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
if len(sys.argv)>1: engine = pathlib.Path(sys.argv[1])
scene = sys.argv[2] if len(sys.argv)>2 else 'M5Pressure'
files = [root/'autoload/Combat.gd', root/'game/map/CombatArena.gd',
         root/'game/map/mapTown/Town.gd', root/'game/guns/BaseGun.gd']
files += list((root/'game/monster').glob('*.gd'))
files += list((root/'game/bullets').glob('*.gd'))
files += list((root/'game/effects').glob('*.gd'))
files += [root/'game/guns/MechanismGun.gd',root/'autoload/server/LevelServer.gd']
runner = root/'tests'/f'{scene}.gd'
backup = {p:p.read_bytes() for p in files+[runner] if p.exists()}
try:
    for p, raw in backup.items():
        s = raw.decode('utf-8-sig').replace('\r\n','\n')
        if p == runner:
            if scene == 'M5Pressure':
                s = s.replace('func finish():', 'func finish():\n\tpreload("res://tests/M6ProfileScope.gd").report()')
            else:
                s = s.replace('\tprint("M5 BOSS COMBAT SUMMARY', '\tpreload("res://tests/M6ProfileScope.gd").report()\n\tprint("M5 BOSS COMBAT SUMMARY')
        else:
            chunks = re.split(r'(?=^func )', s, flags=re.M)
            for i, chunk in enumerate(chunks):
                if not chunk.startswith('func ') or 'await ' in chunk: continue
                first, sep, body = chunk.partition('\n')
                if not first.rstrip().endswith(':'): continue
                name = re.match(r'func (\w+)',first)[1]
                key = f'{p.relative_to(root).as_posix()}:{name}'
                if p.name == 'MechanismProjectile.gd':
                    expr = repr(key+' / ').replace("'",'"')+'+str(spec.get("mode","unknown"))'
                elif p.name == 'TacticalEnemy.gd':
                    expr = repr(key+' / ').replace("'",'"')+'+role'
                else: expr = '"'+key+'"'
                chunks[i] = first+sep+'\tvar _m6_scope = preload("res://tests/M6ProfileScope.gd").new('+expr+')\n'+body
            s = ''.join(chunks)
        p.write_text(s,encoding='utf-8')
    output = root/'docs/iteration/evidence/m6'/f'profile-{scene}.txt'
    with output.open('w',encoding='utf-8') as log:
        result = subprocess.run([str(engine),'--headless','--max-fps','160','--path',str(root),f'res://tests/{scene}.tscn'],stdout=log,stderr=subprocess.STDOUT,timeout=150)
    print('profile exit', result.returncode)
finally:
    for p, raw in backup.items(): p.write_bytes(raw)
