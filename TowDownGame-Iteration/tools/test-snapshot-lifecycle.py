"""Exercise cleanup boundaries and normal success/failure process exits."""
import json
import pathlib
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from snapshot_lifecycle import remove_owned_tree

root = pathlib.Path(__file__).resolve().parents[1]
support = root.parent / 'archive/workspace-support'
out = root / 'docs/iteration/evidence/m12'
out.mkdir(parents=True, exist_ok=True)
owner = pathlib.Path(tempfile.mkdtemp(prefix='m12-lifecycle-', dir=support))
results = []
try:
    for target in [owner, owner.parent]:
        try:
            remove_owned_tree(target, owner)
            results.append(False)
        except ValueError:
            results.append(True)
    for code in [0, 1]:
        script = '''import sys,pathlib
sys.path.insert(0,sys.argv[1])
sys.dont_write_bytecode = True
from snapshot_lifecycle import allocate
p=allocate(pathlib.Path(sys.argv[2]),"m12","probe")
(p/"fixture.txt").write_text("temporary workspace")
print(p,flush=True)
raise SystemExit(int(sys.argv[3]))
'''
        result = subprocess.run([sys.executable, '-B', '-c', script, str(root/'tools'), str(owner), str(code)],
                                capture_output=True, text=True)
        snapshot = pathlib.Path(result.stdout.strip())
        results.append(result.returncode == code and not snapshot.exists())
finally:
    remove_owned_tree(owner, support)
(out/'lifecycle-tests.json').write_text(json.dumps(dict(owner_and_escape_rejected=results[:2],
    success_and_failure_removed=results[2:], passed=all(results)), indent=2), encoding='utf-8')
print('LIFECYCLE_CHECKS', results)
sys.exit(0 if len(results)==4 and all(results) else 1)
