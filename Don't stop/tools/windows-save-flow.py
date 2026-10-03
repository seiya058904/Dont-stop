"""Real Windows release input and process-restart recovery, isolated APPDATA.

Usage: python tools/windows-save-flow.py EXE OUTPUT_DIR
Requires the existing screenshot skill's Windows helper for game-window capture.
"""
import ctypes
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

exe, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
user32 = ctypes.windll.user32
user32.SetProcessDPIAware()
user32.GetClientRect.argtypes = [w.HWND, ctypes.POINTER(w.RECT)]
user32.ClientToScreen.argtypes = [w.HWND, ctypes.POINTER(w.POINT)]
user32.SetForegroundWindow.argtypes = [w.HWND]
user32.GetWindowRect.argtypes = [w.HWND, ctypes.POINTER(w.RECT)]
rect_pattern = re.compile(r'rect (\S+) id=\d+ text="([^"]*)" x=[\d.-]+ y=[\d.-]+ w=[\d.-]+ h=[\d.-]+ cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)')
helper = Path(os.environ['USERPROFILE']) / '.codex/skills/screenshot/scripts/take_screenshot.ps1'
report = {'checks': []}
proc = None
handle = None
log = None


def state():
    text = log.read_text(encoding='utf-8', errors='replace') if log.exists() else ''
    rects = {m[1]: {'x': float(m[3]), 'y': float(m[4]), 'visible': m[5] == 'true'} for m in rect_pattern.finditer(text)}
    carries = re.findall(r'^\[loadout\] (.+)\n', text, re.M)
    probes = re.findall(r'^\[probe\] sess=.+$', text, re.M)
    return rects, json.loads(carries[-1]) if carries else None, probes[-1] if probes else '', text


def until(fn, message, seconds=70):
    end = time.monotonic() + seconds
    while not fn():
        if time.monotonic() > end or proc.poll() is not None:
            raise RuntimeError(message)
        time.sleep(.1)


def click(tag):
    until(lambda: state()[0].get(tag, {}).get('visible'), 'missing ' + tag)
    rect = state()[0][tag]
    client = w.RECT()
    user32.GetClientRect(handle, ctypes.byref(client))
    point = w.POINT(0, 0)
    user32.ClientToScreen(handle, ctypes.byref(point))
    scale = min(client.right / 410, client.bottom / 230)
    x = point.x + (client.right - 410 * scale) / 2 + rect['x'] * scale
    y = point.y + (client.bottom - 230 * scale) / 2 + rect['y'] * scale
    user32.SetForegroundWindow(handle)
    user32.SetCursorPos(round(x), round(y))
    user32.mouse_event(2, 0, 0, 0, 0)
    time.sleep(.06)
    user32.mouse_event(4, 0, 0, 0, 0)
    time.sleep(.6)


def key(vk, duration=.06):
    user32.SetForegroundWindow(handle)
    scan = user32.MapVirtualKeyW(vk, 0)
    user32.keybd_event(vk, scan, 0, 0)
    time.sleep(duration)
    user32.keybd_event(vk, scan, 2, 0)


def capture(name):
    bounds = w.RECT()
    user32.GetWindowRect(handle, ctypes.byref(bounds))
    # The helper's PowerShell process may be DPI-unaware. Pass this driver's
    # physical game-window bounds so CopyFromScreen cannot clip scaled pixels.
    region = f'{bounds.left},{bounds.top},{bounds.right-bounds.left},{bounds.bottom-bounds.top}'
    subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', '-File', str(helper),
                    '-Region', region, '-Path', str(output / (name + '.png'))],
                   check=True, stdout=subprocess.DEVNULL, timeout=20, creationflags=0x08000000)
    user32.SetForegroundWindow(handle)


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    report['checks'].append(message)
    print('PASS', message, flush=True)


def launch(index):
    global proc, handle, log
    log = output / f'input-{index}.log'
    env = os.environ.copy()
    env['APPDATA'] = str(output / 'user')
    proc = subprocess.Popen([str(exe), '--resolution', '1000x562', '--position', '10,10',
                             '--log-file', str(log), '--', '--probe'], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    handles = []
    callback_type = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)

    @callback_type
    def visit(hwnd, _param):
        pid = w.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == proc.pid and user32.IsWindowVisible(hwnd):
            handles.append(hwnd)
        return True

    def find_window():
        user32.EnumWindows(visit, 0)
        return handles

    until(find_window, 'release window not visible')
    handle = handles[0]
    user32.SetWindowPos(handle, None, 10, 10, 0, 0, 1)
    user32.SetForegroundWindow(handle)
    click('menu-start-button')
    until(lambda: state()[1], 'camp did not open')


def quit_product():
    click('camp-settings-button')
    click('native-exit')
    check(proc.wait(timeout=20) == 0, 'production exit completes cleanly')


try:
    launch(1)
    click('camp-search-box')
    key(ord('6'))
    time.sleep(.4)
    click('camp-entry-6')
    click('camp-action-0')
    until(lambda: state()[1] and 6 in state()[1]["owned"] and state()[1]["saved"], "purchase was not saved")
    carry = state()[1]
    check(6 in carry['owned'] and carry['saved'], 'release purchase is saved')
    capture('purchased')
    save = output / 'user/TowDownGame/camp-v1.json'
    check(save.exists() and any(int(g['id']) == 6 for g in json.loads(save.read_text(encoding='utf-8'))['weapons']),
          'native save file contains purchased weapon')
    quit_product()
    launch(2)
    check(6 in state()[1]['owned'] and 6 in state()[1]['slots'], 'new release process restores ownership and slots')
    capture('restored')
    kernel = ctypes.windll.kernel32
    kernel.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p, w.DWORD, w.DWORD, w.HANDLE]
    kernel.CreateFileW.restype = w.HANDLE
    kernel.CloseHandle.argtypes = [w.HANDLE]
    locked = kernel.CreateFileW(str(save), 0x80000000, 3, None, 3, 0x80, None)
    if locked == ctypes.c_void_p(-1).value:
        raise RuntimeError('could not establish isolated file replacement fault')
    previous_bytes = save.read_bytes()
    try:
        click('camp-search-box')
        user32.keybd_event(17, 0, 0, 0)
        key(ord('A'))
        user32.keybd_event(17, 0, 2, 0)
        key(ord('1'))
        time.sleep(.4)
        click('camp-entry-1')
        click('camp-action-0')
        until(lambda: state()[1] and 1 in state()[1]["owned"] and not state()[1]["saved"], "fault was not observed")
        carry = state()[1]
        paid = carry['gold']
        check(1 in carry['owned'] and not carry['saved'], 'native replacement failure retains purchased memory and reports unsaved')
        check(save.read_bytes() == previous_bytes, 'native replacement failure preserves previous save byte for byte')
        capture('replacement-failed')
    finally:
        kernel.CloseHandle(locked)
    click('camp-save-retry')
    until(lambda: state()[1]["saved"], 'retry was not saved')
    check(state()[1]['saved'] and state()[1]['gold'] == paid, 'native retry saves without charging again')
    click('camp-search-box')
    user32.keybd_event(17, 0, 0, 0)
    key(ord('A'))
    user32.keybd_event(17, 0, 2, 0)
    key(ord('6'))
    time.sleep(.4)
    click('camp-entry-6')
    if state()[1]['equipped'] != 6:
        click('camp-action-0')
    click('camp-close-button')
    until(lambda: 'panels=0' in state()[2] and 'gun=6 ' in state()[2], 'practice input did not activate')
    ammo = int(re.search(r'bullets=(\d+)', state()[2])[1])
    client = w.RECT()
    user32.GetClientRect(handle, ctypes.byref(client))
    point = w.POINT(round(client.right * .7), round(client.bottom * .5))
    user32.ClientToScreen(handle, ctypes.byref(point))
    user32.SetCursorPos(point.x, point.y)
    user32.mouse_event(2, 0, 0, 0, 0)
    time.sleep(.18)
    user32.mouse_event(4, 0, 0, 0, 0)
    until(lambda: int(re.search(r'bullets=(\d+)', state()[2])[1]) < ammo, 'actual mouse input did not fire')
    check(True, 'mouse input fires W6 and consumes ammo')
    key(ord('R'))
    until(lambda: re.search(r'bullets=(\d+)/(\d+)', state()[2])[1] == re.search(r'bullets=(\d+)/(\d+)', state()[2])[2], 'physical R input did not complete reload', 12)
    check(True, 'physical R input reloads the real magazine')
    capture('practice')
    key(9)
    until(lambda: re.search(r'panels=[1-9]', state()[2]), 'Tab did not open camp')
    quit_product()
    errors = [line for p in output.glob('input-*.log') for line in p.read_text(encoding='utf-8', errors='replace').splitlines()
              if line.startswith(('ERROR:', 'SCRIPT ERROR:', 'FAIL '))]
    check(not errors, 'both release processes have no engine errors')
    report['success'] = True
except Exception as error:
    report['error'] = str(error)
    print('FAIL', error, flush=True)
    if handle:
        try:
            capture('failure')
        except Exception:
            pass
finally:
    if proc and proc.poll() is None:
        proc.terminate()
        proc.wait(timeout=10)
    (output / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
sys.exit(0 if report.get('success') else 1)
