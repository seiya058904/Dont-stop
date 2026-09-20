"""Post-run statistics only: never runs in a measured fight."""
import bisect, json, math, sys
from pathlib import Path

def stats(values):
    if not values: return None
    s=sorted(values)
    return {"frames":len(s),"avg":sum(s)/len(s),"p95":s[math.ceil(len(s)*.95)-1],"p99":s[math.ceil(len(s)*.99)-1],"max":s[-1],"over33_percent":100*sum(v>33.3 for v in s)/len(s),"over50":sum(v>50 for v in s)}

def summarize(path):
    d=json.loads(path.read_text(encoding="utf-8")); r=d.get("raw_frames")
    if not r: return {"file":path.name,"missing_raw":True}
    ms=r["ms"]; ts=r["combat_wall_seconds"]
    hot=[v for v,t in zip(ms,ts) if t>=5]
    window=[]; left=0; worst=None
    for right,(t,v) in enumerate(zip(ts,ms)):
        bisect.insort(window,v)
        while ts[left]<t-5:
            window.pop(bisect.bisect_left(window,ms[left]));left+=1
        if t>=5:
            p95=window[math.ceil(len(window)*.95)-1]
            if worst is None or p95>worst["p95"]: worst={"from_s":t-5,"to_s":t,**stats(window)}
    longest=run=0
    for v in ms:
        run=run+v if v>33.3 else 0;longest=max(longest,run)
    rows=r["load_samples"]; hz=r["physics_hz"]; sim=r["effective_sim_seconds"]
    weights=[max(0,(rows[i+1]["tick"]-x["tick"])/hz) if i+1<len(rows) else max(0,sim-x["tick"]/hz) for i,x in enumerate(rows)]
    weight=sum(weights)
    def weighted(k):return sum(x.get(k,0)*w for x,w in zip(rows,weights))/weight if weight else None
    wall=r.get("measured_wall_s",ts[-1] if ts else 0)-r.get("paused_ms",0)/1000
    h=stats(hot)
    return {"file":path.name,"full":stats(ms),"first5":stats([v for v,t in zip(ms,ts) if t<5]),"hot":h,"worst5":worst,"longest_over33_ms":longest,"sim_s":sim,"wall_s":wall,"sim_wall":sim/wall if wall else None,"timing_pass":bool(h and h["p95"]<=18.5 and h["p99"]<=25 and h["over33_percent"]<.5 and sim/wall>=.98),"unclassified_over50":[{"wall_s":t,"ms":v} for v,t in zip(ms,ts) if v>50],"load":{"weighted_ordinary":weighted("ordinary"),"weighted_elite":weighted("elite"),"weighted_visible":weighted("visible"),"weighted_shots":weighted("shots_live"),"shots_peak":max((x["shots_live"] for x in rows),default=0),"near_cap_sim_percent":100*sum(w for x,w in zip(rows,weights) if x["shots_live"]>=162)/weight if weight else 0,"last":rows[-1] if rows else {}},"boss_complete":r.get("boss_complete"),"timeout":r.get("measurement_timeout"),"errors":d.get("errors",d.get("diagnostics",[])),"surface":r.get("surface"),"build":d.get("build")}

if __name__=="__main__":
    print(json.dumps([summarize(Path(p)) for p in sys.argv[1:]],ensure_ascii=False,indent=2))
