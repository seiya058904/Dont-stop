#!/usr/bin/env python3
"""B8 evidence summariser.

Reads the frozen fixture's JSON output and prints the tables the report quotes. It reads files
only - it never re-runs anything and never edits an evidence file, so a number in the report can
always be traced back to the batch and seed that produced it.

Usage:
  python tools/b8-summary.py <evidence_dir> normal-pre-s22 [normal-pre-s26 ...]
  python tools/b8-summary.py <evidence_dir> --sequence normal-pre-sequence
  python tools/b8-summary.py <evidence_dir> --boss boss-fair-pre-s30 boss-fair-pre-s40
"""
import json
import os
import sys
from collections import defaultdict


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def ordered(row):
    for key in ("stage", "seed"):
        if key in row and row[key] is not None:
            pass
    return row


def table(rows, title):
    print(f"\n### {title}")
    header = (f"{'stage':>5} {'seed':>6} {'pin':>4} {'lv':>3} {'outcome':>9} {'sec':>6} "
              f"{'alive':>6} {'peak':>5} {'near80':>6} {'proj':>5} {'zone':>5} {'haz':>4} "
              f"{'elite':>5} {'spec':>5} {'spawns':>6} {'dmg':>7} {'hits':>5} {'move':>7} {'shots':>6}")
    print(header)
    for row in rows:
        print(f"{row.get('stage', 0):>5} {row.get('seed', 0):>6} {row.get('pin_level', 0):>4} "
              f"{row.get('level_before', 0):>3} {row.get('outcome', '?'):>9} "
              f"{row.get('seconds', 0.0):>6.1f} {row.get('alive_mean', 0.0):>6.1f} "
              f"{row.get('alive_peak', 0):>5} {row.get('near80_peak', 0):>6} "
              f"{row.get('projectile_peak', 0):>5} {row.get('hostile_zone_peak', 0):>5} "
              f"{row.get('hazard_peak', 0):>4} {row.get('elite_peak', 0):>5} "
              f"{row.get('special_ratio', 0.0):>5.2f} {row.get('spawns', 0):>6} "
              f"{row.get('damage_total', 0.0):>7.2f} {row.get('hits_total', 0):>5} "
              f"{row.get('movement', 0.0):>7.0f} {row.get('shots', 0):>6}")


def clear_ladder(rows):
    print("\n### clear rate")
    by_stage = defaultdict(list)
    for row in rows:
        by_stage[row["stage"]].append(row)
    for stage in sorted(by_stage):
        group = by_stage[stage]
        clears = sum(1 for row in group if row.get("outcome") == "clear")
        deaths = sum(1 for row in group if row.get("outcome") == "death")
        trunc = sum(1 for row in group if row.get("outcome") == "truncated")
        times = [row.get("seconds", 0.0) for row in group if row.get("outcome") == "clear"]
        mean = sum(times) / len(times) if times else 0.0
        print(f"  stage {stage}: {clears}/{len(group)} clear, {deaths} death, {trunc} truncated, "
              f"mean clear time {mean:.1f}s")
    stages = sorted(by_stage)
    if len(stages) >= 2:
        rates = [sum(1 for r in by_stage[s] if r.get("outcome") == "clear") / len(by_stage[s])
                 for s in stages]
        monotone = all(rates[i] >= rates[i + 1] for i in range(len(rates) - 1))
        print(f"  ladder {stages} -> {[round(r, 2) for r in rates]}: "
              f"{'monotone (harder later)' if monotone else 'NOT monotone'}")


def damage_split(rows):
    print("\n### damage taken by category")
    totals = defaultdict(float)
    hits = defaultdict(int)
    for row in rows:
        for entry in row.get("damage_by_category", []):
            totals[entry["category"]] += entry["applied"]
            hits[entry["category"]] += entry["hits"]
    grand = sum(totals.values())
    for key, value in sorted(totals.items(), key=lambda kv: -kv[1]):
        print(f"  {key:<24} {value:>8.2f}  {value / grand * 100 if grand else 0:>5.1f}%  {hits[key]:>5} hits")
    print(f"  {'TOTAL':<24} {grand:>8.2f}")
    print("\n### damage taken by mechanism tag")
    tag_totals = defaultdict(float)
    tag_hits = defaultdict(int)
    for row in rows:
        for entry in row.get("damage_by_tag", []):
            tag_totals[entry["tag"]] += entry["applied"]
            tag_hits[entry["tag"]] += entry["hits"]
    for key, value in sorted(tag_totals.items(), key=lambda kv: -kv[1]):
        print(f"  {key:<24} {value:>8.2f}  {value / grand * 100 if grand else 0:>5.1f}%  {tag_hits[key]:>5} hits")


def death_causes(rows):
    print("\n### lethal mechanism per death")
    for row in rows:
        if row.get("outcome") != "death":
            continue
        snapshot = row.get("death_snapshot") or {}
        lethal = snapshot.get("lethal") or {}
        sequence = snapshot.get("sequence") or []
        recent = ", ".join(f"{e['tag']}({e['applied']:.2f})" for e in sequence[-6:])
        print(f"  stage {row['stage']} seed {row['seed']} died at {row.get('death_at', 0):.1f}s "
              f"to {lethal.get('tag', '?')} [{lethal.get('category', '?')}] "
              f"by {lethal.get('attacker', '')} hp_before {lethal.get('hp_before', 0):.2f}")
        print(f"    zones at death {snapshot.get('zones', {})} hazards {snapshot.get('hazards', {})} "
              f"projectiles {snapshot.get('projectiles', 0)} fog {snapshot.get('fog', False)}")
        print(f"    last 3s: {recent}")
        print(f"    escapes at death: {snapshot.get('escape', {})}")


def fairness(rows):
    print("\n### escape-availability")
    for row in rows:
        print(f"  stage {row['stage']} seed {row['seed']}: samples {row.get('probe_samples', 0)} "
              f"fair-denial {row.get('denial_samples', 0)} strict {row.get('strict_denial_samples', 0)} "
              f"geometric {row.get('geometric_denial_samples', 0)} "
              f"longest streak {row.get('denial_streak_peak', 0)} "
              f"events {len(row.get('denial_events') or [])} "
              f"modes {row.get('denial_modes', [])} "
              f"rooted-hits {row.get('rooted_hits', 0)} post-root {row.get('post_root_hits', 0)}")


def boss_verdicts(verdicts):
    print("\n### boss fairness verdicts")
    for entry in verdicts:
        print(f"  stage {entry['stage']} {entry['outcome']} at {entry['seconds']:.1f}s "
              f"killed by {entry.get('killer', '')} [{entry.get('killer_category', '')}] "
              f"phase {entry.get('death_phase', '')} action {entry.get('death_boss_action', '')}")
        print(f"    zones {entry.get('death_zones', {})} hazards {entry.get('death_hazards', {})} "
              f"projectiles {entry.get('death_projectiles', 0)} fog {entry.get('death_fog', False)}")
        print(f"    escapes at death: {entry.get('escape_at_death', {})}")
        print(f"    simultaneous footprints {entry.get('simultaneous_footprints', 0)} "
              f"max combo {entry.get('max_combo', 0)} denial events {entry.get('denial_events', 0)} "
              f"streak {entry.get('denial_streak_peak', 0)} -> "
              f"{'UNAVOIDABLE' if entry.get('unavoidable') else 'avoidable / not a defect'}")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    base = sys.argv[1]
    rows = []
    for name in sys.argv[2:]:
        if name == "--sequence":
            continue
        path = os.path.join(base, name + ".json")
        if not os.path.exists(path):
            print(f"  missing {path}")
            continue
        data = load(path)
        if isinstance(data, dict) and "rows" in data:
            rows.extend(data["rows"])
            if data.get("verdicts"):
                boss_verdicts(data["verdicts"])
        elif isinstance(data, list):
            rows.extend(data)
    if rows:
        rows.sort(key=lambda r: (r.get("stage", 0), r.get("seed", 0)))
        table(rows, "runs")
        clear_ladder(rows)
        damage_split(rows)
        death_causes(rows)
        fairness(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
