"""Observe the exported executable; capture only its own window, with ACK pacing."""
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import sys

exe=Path(sys.argv[1]).resolve()
out=Path(sys.argv[2]).resolve(); out.mkdir(parents=True,exist_ok=True)
helper=Path.home()/'.codex/skills/screenshot/scripts/take_screenshot.ps1'
user=ctypes.windll.user32
ctypes.windll.shcore.SetProcessDpiAwareness(2)
callback_type=ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
user.EnumWindows.argtypes=[callback_type,wintypes.LPARAM]
user.GetWindowThreadProcessId.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.DWORD)]
user.IsWindowVisible.argtypes=[wintypes.HWND]
user.SetWindowPos.argtypes=[wintypes.HWND,wintypes.HWND,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,wintypes.UINT]
user.GetWindowRect.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.RECT)]
user.ShowWindow.argtypes=[wintypes.HWND,ctypes.c_int]
def window(pid):
    found=[]
    @callback_type
    def visit(handle,_):
        owner=wintypes.DWORD(); user.GetWindowThreadProcessId(handle,ctypes.byref(owner))
        if owner.value==pid:
            rect=wintypes.RECT(); user.GetWindowRect(handle,ctypes.byref(rect))
            found.append(((rect.right-rect.left)*(rect.bottom-rect.top),handle))
        return True
    user.EnumWindows(visit,0)
    if not found: raise RuntimeError('export window not found')
    return max(found)[1]

args=[str(exe),'--verbose','--','--smoke','--b17-visual','--b17-physical','--b17-output='+str(out)]
startup=subprocess.STARTUPINFO(); startup.dwFlags=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=5
process=subprocess.Popen(args,startupinfo=startup,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
captures=[]
try:
    with (out/'run.log').open('w',encoding='utf-8') as log:
        for line in process.stdout:
            log.write(line); log.flush()
            if line.startswith('B17_CAPTURE '):
                name=line.strip().split(' ',1)[1]
                handle=window(process.pid)
                user.ShowWindow(handle,5)
                # Keep only this test window above other windows, without activating it.
                user.SetWindowPos(handle,-1,0,0,0,0,0x13)
                target=out/(name+'-window.png')
                quote=lambda value: "'"+str(value).replace("'","''")+"'"
                script='Add-Type \'using System.Runtime.InteropServices; public class B17Dpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }\'\n[B17Dpi]::SetProcessDPIAware() | Out-Null\n'
                script+='& '+quote(helper)+' -WindowHandle '+str(handle)+' -Path '+quote(target)+'\n'
                subprocess.run(['powershell','-NoProfile','-Command','-'],input=script,text=True,check=True,stdout=subprocess.DEVNULL,timeout=15)
                captures.append({'name':name,'window_handle':handle,'file':target.name})
                (out/(name+'.ack')).write_text('captured',encoding='utf-8')
            elif 'ERROR' in line or 'WARNING' in line or 'B17_VISUAL' in line: print(line.strip(),flush=True)
    code=process.wait(timeout=15)
finally:
    if process.poll() is None: process.terminate()
(out/'capture-index.json').write_text(json.dumps({'exe':str(exe),'exit':code,'captures':captures},indent=1),encoding='utf-8')
print('exported native exit',code,'physical captures',len(captures))
raise SystemExit(code)
