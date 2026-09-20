"""Record exported Windows viewport captures at each actual window size; own process only."""
from pathlib import Path
import subprocess, re, sys
root=Path(__file__).resolve().parents[1]
out=root/'evidence/visual-upgrade-20260919'/sys.argv[1]
out.mkdir(exist_ok=False)
exe=root/"build/b16-windows/Don't stop.exe"
args=[str(exe),'--position','0,0','--','--smoke','--b16-ui','--b16-output='+str(out/'internal')]
with (out/'console.log').open('w',encoding='utf-8') as log:
 proc=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
 for line in proc.stdout:
  log.write(line);log.flush()
  m=re.search(r'B16_NATIVE_UI (\w+) window=\((\d+), (\d+)\)',line)
  if m:
   page,w,h=m.groups()
   print(page,w,h,flush=True)
 code=proc.wait(timeout=120)
text=(out/'console.log').read_text(encoding='utf-8')
issues=[l for l in text.splitlines() if l.startswith(('ERROR:','SCRIPT ERROR:','FAIL '))]
print('exit',code,'issues',len(issues),flush=True)
sys.exit(1 if code or issues else 0)
