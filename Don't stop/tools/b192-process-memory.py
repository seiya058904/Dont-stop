"""Sample only the launched browser process tree; no unrelated processes."""
import json, sys, time
from pathlib import Path
import psutil
root = psutil.Process(int(sys.argv[1]))
rows = []
started = time.monotonic()
while root.is_running() and time.monotonic()-started < 600:
    members = []
    try:
        for process in [root, *root.children(recursive=True)]:
            try:
                info = process.memory_info()
                members.append({"pid":process.pid,"rss":info.rss,"private":getattr(info,"private",None)})
            except (psutil.NoSuchProcess,psutil.AccessDenied): pass
    except psutil.NoSuchProcess: break
    rows.append({"wall_s":time.monotonic()-started,"rss":sum(p["rss"] for p in members),"members":members})
    time.sleep(2)
Path(sys.argv[2]).write_text(json.dumps(rows),encoding="utf-8")
