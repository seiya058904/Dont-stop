"""Identical 60-zone fixture, sequential M7 / pre-R1 M8 / R1 / R1 / M8 / M7."""
import json, pathlib, re, shutil, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'docs/iteration/evidence/m8'
rows=[]
suffix='-offscreen' if '--offscreen' in sys.argv else ('-verified' if '--verified' in sys.argv else ('-isolated' if '--isolated' in sys.argv else ('-final' if '--final' in sys.argv else '')))
for version in ['M7','M8','M8-R1','M8-R1','M8','M7']:
    name=f'r1-perf-{len(rows):02}-{version}'+suffix
    command=[sys.executable,str(root/'tools/run-m8.py'),name,'M8Perf','--render','telegraph']
    folder=out
    if version!='M8-R1':
        command += ['--baseline' if version=='M7' else '--pre-r1']
        folder=root.parent/('archive/workspace-support/m8-baseline' if version=='M7' else 'archive/workspace-support/m8-r1-baseline')/'TowDownGame-Iteration/docs/iteration/evidence/m8'
    result=subprocess.run(command,capture_output=True,text=True,timeout=180)
    if folder!=out:
        for path in folder.glob(name+'*'): shutil.copy2(path,out/path.name)
    content=(out/f'{name}.txt').read_text(encoding='utf-8')
    match=re.search(r'^M8 PERF (\{.*\})$',content,re.M)
    row=dict(version=version,scenario='telegraph',code=result.returncode,metrics=json.loads(match[1]) if match else None,log=name+'.txt')
    rows.append(row); (out/f'performance-r1{suffix}.json').write_text(json.dumps(rows,indent=2),encoding='utf-8'); print(json.dumps(row),flush=True)
    if row['code']!=0: sys.exit(1)
sys.exit(0 if all(r['code']==0 for r in rows) else 1)
