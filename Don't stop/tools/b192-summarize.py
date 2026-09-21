"""Post-run statistics only: never runs in a measured fight."""
import bisect, json, math, sys
from pathlib import Path

def stats(values):
    if not values: return None
    s=sorted(values)
    return {"frames":len(s),"avg":sum(s)/len(s),"p95":s[math.ceil(len(s)*.95)-1],"p99":s[math.ceil(len(s)*.99)-1],"max":s[-1],"over33_percent":100*sum(v>33.3 for v in s)/len(s),"over50":sum(v>50 for v in s),"over100":sum(v>100 for v in s),"over250":sum(v>250 for v in s),"over1000":sum(v>1000 for v in s)}

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
    full=stats(ms)
    # Duration and mode are explicit, so a 15-second diagnostic cannot silently
    # become a formal PASS. Boss completion is a separate coverage requirement.
    stage = next(iter(r.get("round_contexts", [])), {}).get("stage")
    required_seconds = 150 if stage == 40 else (30 if r.get("workload_scenario") == "P" else 45)
    duration_observed = (r.get("boss_complete") and not r.get("controlled_boss")) if stage == 40 else sim >= required_seconds
    formal = r.get("mode") == "formal" and r.get("requested_seconds",0) >= required_seconds and duration_observed
    simultaneous = {}
    for key in ("alive", "drawing", "on_screen"):
        flag = "simultaneous_180_" + key
        simultaneous[key + "_observed_sim_s"] = sum(
            max(0,(b["tick"]-a["tick"])/hz)
            for a,b in zip(rows,rows[1:])
            if a.get("round") == b.get("round") and a.get(flag) and b.get(flag))
    simultaneous["method"] = "adjacent 100ms gauge samples both meet 180+180; sampled coverage, not continuous proof"
    return {"file":path.name,"full":full,"first5":stats([v for v,t in zip(ms,ts) if t<5]),"hot":h,"worst5":worst,"longest_over33_ms":longest,"sim_s":sim,"wall_s":wall,"sim_wall":sim/wall if wall else None,"mode":r.get("mode","legacy-unclassified"),"formal_duration_met":formal,"simultaneous_180":simultaneous,"long_frames":r.get("long_frames",[]),"timing_pass":bool(formal and full and full["p95"]<=18.5 and full["p99"]<=25 and full["over33_percent"]<.5 and wall>0 and sim/wall>=.98),"unclassified_over50":[{"wall_s":t,"ms":v} for v,t in zip(ms,ts) if v>50],"load":{"weighted_ordinary":weighted("ordinary"),"weighted_elite":weighted("elite"),"weighted_visible":weighted("visible"),"weighted_shots":weighted("shots_live"),"shots_peak":max((x["shots_live"] for x in rows),default=0),"near_cap_sim_percent":100*sum(w for x,w in zip(rows,weights) if x["shots_live"]>=162)/weight if weight else 0,"last":rows[-1] if rows else {}},"boss_complete":r.get("boss_complete"),"timeout":r.get("measurement_timeout"),"errors":d.get("errors",d.get("diagnostics",[])),"surface":r.get("surface"),"build":d.get("build")}

if __name__=="__main__":
    print(json.dumps([summarize(Path(p)) for p in sys.argv[1:]],ensure_ascii=False,indent=2))
