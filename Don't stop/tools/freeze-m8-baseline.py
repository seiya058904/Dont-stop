"""Preserve the verified M7 source and imported assets for paired M8 comparisons."""
import hashlib, json, os, pathlib, shutil, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
target = root.parent/'archive/workspace-support/m8-baseline/TowDownGame-Iteration'
assert not target.exists(), 'Baseline already exists; never overwrite it'
assert subprocess.check_output(['git','rev-parse','--short','HEAD'],cwd=root.parent,text=True).strip() == '55a22ae'
def asset(source, destination):
    path = pathlib.Path(source)
    if path.suffix in ['.gd','.tscn','.tres','.godot','.cfg','.py','.ps1','.uid'] or ('.godot' in path.parts and 'imported' not in path.parts):
        return shutil.copy2(source,destination)
    try: os.link(source,destination)
    except OSError: shutil.copy2(source,destination)
    return destination
shutil.copytree(root,target,copy_function=asset,ignore=shutil.ignore_patterns('evidence','docs','shader_cache','editor','__pycache__','*.log'))
paths = [p for folder in ['autoload','game','ui'] for p in (target/folder).rglob('*.gd')]
record = {p.relative_to(target).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
(root/'docs/iteration/evidence/m8/baseline-source.json').write_text(json.dumps({'commit':'55a22ae','source':record},indent=2),encoding='utf-8')
print(target)
