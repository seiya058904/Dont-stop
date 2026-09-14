"""Sequential paired GPU runs; launch only after other game tests finish."""
import json,pathlib,re,subprocess,sys,time
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'docs/iteration/evidence/m8'
baseline=root.parent/'archive/workspace-support/m8-baseline/TowDownGame-Iteration/docs/iteration/evidence/m8'
rows=[]
scenarios=['normal','late','boss','projectile','telegraph','particle']
final_fx='--final-fx' in sys.argv
if final_fx: scenarios=['telegraph','particle']
destination='performance-final-fx.json' if final_fx else 'performance.json'
for scenario in scenarios:
    for version in ['M7','M8','M8','M7']:
        name=f'perf-{scenario}-{len(rows):02}-{version}'+('-final-fx' if final_fx else '')
        command=[sys.executable,str(root/'tools/run-m8.py'),name,'M8Perf','--render',scenario]
        if version=='M7': command+=['--baseline']
        result=subprocess.run(command,capture_output=True,text=True,timeout=180)
        folder=baseline if version=='M7' else out
        content=(folder/f'{name}.txt').read_text(encoding='utf-8')
        if version=='M7':
            import shutil
            for path in folder.glob(name+'*'): shutil.copy2(path,out/path.name)
        match=re.search(r'^M8 PERF (\{.*\})$',content,re.M)
        row=dict(version=version,scenario=scenario,code=result.returncode,metrics=json.loads(match[1]) if match else None,log=name+'.txt')
        rows.append(row); (out/destination).write_text(json.dumps(rows,indent=2),encoding='utf-8'); print(json.dumps(row),flush=True)
sys.exit(0 if all(r['code']==0 for r in rows) else 1)
