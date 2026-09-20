"""Seal current source and measured evidence; run after collecting, never on CI."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'docs/iteration/evidence/b17'
def entry(path):
    content = path.read_text(encoding='utf-8').replace('\r\n','\n')
    return {'path':path.relative_to(root).as_posix(), 'sha256':hashlib.sha256(content.encode()).hexdigest()}
source = []
for directory in ['autoload','game','ui']:
    source.extend(p for p in (root/directory).rglob('*') if p.suffix in ['.gd','.tscn'])
source.extend(root/'tests'/name for name in ['M8Runtime.gd','M9Power.gd','B12WeaponBench.gd','B14HordeBench.gd','B14GrowthMatrix.gd','B14EncounterBench.gd','B17Sources.gd','B17RewardMatrix.gd'])
data = [out/name for name in ['sources.json','reward-matrix.json','growth-matrix.json','horde.json','encounters.json','bosses.json','boss-survival.json','performance.json']]
manifest = {'version':'B17','source':[entry(p) for p in sorted(source)],'data':[entry(p) for p in data],
            'status':'Measured candidate; failures retained, HUMAN_ACCEPTED=false',
            'benchmark_note':'Horde/encounters are new B17 runs. Saved-only isolation added subsequently; live firing path unchanged by that correction. Performance methods differ and are labelled separately.'}
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
print('sealed',len(source),'sources and',len(data),'datasets')
