"""Keep an immutable c8e168e comparison inside workspace support."""
import hashlib, json, os, pathlib, shutil, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
target = root.parent/'archive/workspace-support/m8-r1-baseline/TowDownGame-Iteration'
assert not target.exists() or '--resume-incomplete' in sys.argv, 'Never overwrite a baseline'
assert not (root/'docs/iteration/evidence/m8/r1-baseline-source.json').exists()
assert subprocess.check_output(['git','rev-parse','--short','HEAD'],cwd=root,text=True).strip() == 'c8e168e'
def asset(source,destination):
    path=pathlib.Path(source)
    if path.suffix.lower() not in ['.png','.jpg','.ogg','.mp3','.wav','.ctex','.ttf','.woff','.otf']:
        return shutil.copy2(source,destination)
    try: os.link(source,destination)
    except OSError: shutil.copy2(source,destination)
    return destination
if not target.exists(): shutil.copytree(root,target,copy_function=asset,ignore=shutil.ignore_patterns('evidence','docs','shader_cache','editor','__pycache__','*.log'))
# Restore tracked source exactly; profiling instrumentation is not part of this baseline.
paths=subprocess.check_output(['git','-c','core.quotepath=false','ls-tree','-r','--name-only','c8e168e','TowDownGame-Iteration'],cwd=root.parent).decode('utf-8').splitlines()
for name in paths:
    relative=pathlib.Path(name).relative_to(root.name)
    if relative.parts[0] in ['game','autoload','ui','tests'] or name.endswith('project.godot'):
        destination=target/relative
        destination.parent.mkdir(parents=True,exist_ok=True)
        content=subprocess.check_output(['git','show','c8e168e:'+name],cwd=root.parent)
        if destination.suffix.lower() in ['.png','.jpg','.ogg','.mp3','.wav','.ctex','.ttf','.woff','.otf']:
            assert destination.read_bytes()==content,'Immutable asset differs: '+name
        else: destination.write_bytes(content)
record={p.relative_to(target).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['game','autoload','ui'] for p in (target/folder).rglob('*.gd')}
(root/'docs/iteration/evidence/m8/r1-baseline-source.json').write_text(json.dumps({'commit':'c8e168e','source':record},indent=2),encoding='utf-8')
print(target)
