"""Keep one bounded, reviewable evidence set; leave every original run untouched."""
import hashlib
import json
from pathlib import Path
import shutil

root=Path(__file__).resolve().parents[1]
source=root/'evidence/visual-upgrade-20260919'
dest=root/'docs/iteration/evidence/b14'
dest.mkdir(parents=True,exist_ok=True)
index=[]
for path in sorted(source.glob('b14-*')):
    if not path.is_file() or path.suffix not in ['.json','.log'] or path.name=='b14-pr-body.md':continue
    data=path.read_bytes()
    entry={'path':str(path.relative_to(root)).replace('\\','/'),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    if path.name in ['b14-growth-matrix-after.json','b14-growth-matrix-final.json','b14-catalog-after.json','b14-catalog-final.json']:
        entry['remote_copy']='intermediate observation retained locally; complete original and release matrices included'
        index.append(entry)
        continue
    if path.suffix=='.log' and len(data)>512*1024:
        lines=data.decode('utf-8',errors='replace').splitlines()
        (dest/(path.name+'.excerpt.txt')).write_text('\n'.join(lines[:80]+['[EXCERPT: full original retained locally; hash/size in index]']+lines[-80:])+'\n',encoding='utf-8')
        entry['remote_copy']='head/tail excerpt; full raw retained at original path'
    else:
        shutil.copyfile(path,dest/path.name)
        entry['remote_copy']='complete'
    index.append(entry)
screens={
    'b14-web-final':['02-full.png','03-replaced.png','04-cleared.png','05-restored-reconfigured.png','06-combat-hud.png','result.json'],
    'b14-attack-before':['B04-3-ultimate-active.png','B04-3-ultimate-early-warning.png','E14-warn-beam-locked.png','index.json'],
    'b14-attack-after':['B04-3-ultimate-active.png','B04-3-ultimate-early-warning.png','B04-1-warn-dash-locked.png','E14-warn-beam-locked.png','E14-recover-beam-locked.png','index.json'],
    'b14-web-release':['02-full.png','03-replaced.png','05-restored-reconfigured.png','06-combat-hud.png','result.json']}
for directory,names in screens.items():
    for name in names:
        path=source/directory/name
        if not path.exists():continue
        target=dest/directory/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(path,target)
        index.append({'path':str(path.relative_to(root)).replace('\\','/'),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'remote_copy':'complete selected frame'})
(dest/'index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Text fingerprints are CRLF-independent, matching Godot's explicit runtime verifier.
def row(path):
    text=path.read_text(encoding='utf-8').replace('\r\n','\n')
    return {'path':str(path.relative_to(root)).replace('\\','/'),'sha256':hashlib.sha256(text.encode()).hexdigest()}
inputs=[]
for directory in ['autoload','game','tests']:
    for pattern in ['*.gd','*.tscn']:
        inputs.extend((root/directory).rglob(pattern))
inputs += [root/'project.godot']
data_names=['b14-horde-reference.json','b14-horde-calibrated.json','b14-horde-second-seed.json','b14-growth-matrix-release.json','b14-catalog-release.json',
    'b14-encounter-after2.json','b14-encounter-coverage.json','b14-extension-elite-all.json',
    'b14-extension-boss-before.json','b14-extension-boss-calibrated.json','b14-extension-wave-before.json','b14-extension-wave-after.json','b14-extension-wave-half-after.json']
missing=[name for name in data_names if not (dest/name).exists()]
if missing:raise SystemExit('Missing current evidence, no manifest written: '+', '.join(missing))
manifest={'protocol':'B14 moving-horde and actual-growth contract; historic B12/B13 preserved',
    'source':[row(p) for p in sorted(set(inputs))], 'data':[row(dest/name) for name in data_names],
    'reference_reuse':'The unchanged 21 weapons reuse the B14 reference with identical effective combat parameters; 113/119/124 use paired remeasurement. This is not a v12 build or human acceptance.'}
(dest/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(index)} evidence entries, {len(inputs)} source fingerprints, {sum(p.stat().st_size for p in dest.rglob("*") if p.is_file())} bytes')
