#!/usr/bin/env python3
"""B9 old-vs-new driver comparison.

Reads two sets of frozen evidence and prints the comparison the B9 brief asks for:

  * the same product SHA, the same build, the same 8 HP pool, the same seeds and the same
    fixture, measured once on the OLD driver (B8's saved rows) and once on the NEW driver
    (B9's rows). The only variable is tests/M8Runtime.gd.
  * how much of the measured "difficulty" was the product and how much was a driver that
    could not dodge.
  * the reaction-budget and danger-avoidance telemetry the new driver records.
  * whether the 22 < 26 < 29 difficulty ladder actually holds, judged on clear rate AND mean
    survival AND hits per second AND damage per second rather than on a single clear rate.

It reads files only: it never re-runs anything and never rewrites an evidence file, so every
number here can be traced back to the batch and seed that produced it.

Usage:
  python tools/b9-summary.py <b8_evidence_dir> <b9_evidence_dir> old_tag new_tag [stage ...]
  python tools/b9-summary.py "Don't stop/docs/iteration/evidence/b8" \
      "Don't stop/docs/iteration/evidence/b9" final newdriver 22 26 29
"""
import json
import os
import sys
from collections import defaultdict


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def read_batch(base, tag, stage):
    """Rows for one stage. `tag` may be a comma-separated list, in which case the batches are
    concatenated - that is how the 22-vs-26 ordering is settled at n=10 instead of n=5."""
    rows = []
    for single in str(tag).split(","):
        path = os.path.join(base, "normal-%s-s%d.json" % (single.strip(), stage))
        if os.path.exists(path):
            rows.extend(load(path))
    return rows


def mean(values):
    return sum(values) / len(values) if values else 0.0


def group_stats(rows):
    clears = [r for r in rows if r.get("outcome") == "clear"]
    seconds = [r.get("seconds", 0.0) for r in rows]
    hits = [r.get("hits_total", 0) for r in rows]
    damage = [r.get("damage_total", 0.0) for r in rows]
    total_seconds = sum(seconds) or 1.0
    return {
        "runs": len(rows),
        "clears": len(clears),
        "clear_rate": len(clears) / len(rows) if rows else 0.0,
        "mean_s": mean(seconds),
        "mean_hits_per_s": sum(hits) / total_seconds,
        "mean_damage_per_s": sum(damage) / total_seconds,
        "mean_damage": mean(damage),
        "mean_hits": mean(hits),
        "mean_move": mean([r.get("movement", 0.0) for r in rows]),
        "mean_shots": mean([r.get("shots", 0) for r in rows]),
        "alive_mean": mean([r.get("alive_mean", 0.0) for r in rows]),
        "alive_peak": max([r.get("alive_peak", 0) for r in rows] or [0]),
        "near80_peak": max([r.get("near80_peak", 0) for r in rows] or [0]),
        "projectile_peak": max([r.get("projectile_peak", 0) for r in rows] or [0]),
        "zone_peak": max([r.get("hostile_zone_peak", 0) for r in rows] or [0]),
        "hazard_peak": max([r.get("hazard_peak", 0) for r in rows] or [0]),
        "spawns": mean([r.get("spawns", 0) for r in rows]),
        "special_ratio": mean([r.get("special_ratio", 0.0) for r in rows]),
        "denial_runs": len([r for r in rows if (r.get("denial_events") or [])]),
        "denial_peak": max([r.get("denial_streak_peak", 0) for r in rows] or [0]),
    }


def dodge_stats(rows):
    out = {}
    for key in ("dodge_decisions", "dodge_blocked_candidates", "dodge_scored_candidates",
                "dodge_danger_marks", "dodge_all_danger", "dodge_risky_choices",
                "dodge_unchanged", "dodge_all_blocked"):
        out[key] = sum(int(r.get(key, 0)) for r in rows)
    return out


def category_totals(rows):
    totals = defaultdict(float)
    hits = defaultdict(int)
    for row in rows:
        for entry in row.get("damage_by_category", []):
            totals[entry["category"]] += entry["applied"]
            hits[entry["category"]] += entry["hits"]
    return totals, hits


def difficulty_table(stages, old, new):
    print("\n### difficulty ladder, OLD driver vs NEW driver")
    print(f"{'stage':>5} {'driver':>9} {'clear':>6} {'rate':>5} {'mean_s':>7} {'hits/s':>7} "
          f"{'dmg/s':>6} {'dmg':>6} {'move':>7} {'shots':>6} {'alive':>6} {'peak':>5} "
          f"{'near80':>6} {'proj':>5} {'zone':>5}")
    stats = {}
    for stage in stages:
        for label, source in (("old", old), ("new", new)):
            row = source[stage]
            stats[(stage, label)] = row
            print(f"{stage:>5} {label:>9} {row['clears']:>3}/{row['runs']:<2} "
                  f"{row['clear_rate']:>5.1f} {row['mean_s']:>7.1f} {row['mean_hits_per_s']:>7.2f} "
                  f"{row['mean_damage_per_s']:>6.2f} {row['mean_damage']:>6.2f} "
                  f"{row['mean_move']:>7.0f} {row['mean_shots']:>6.1f} {row['alive_mean']:>6.1f} "
                  f"{row['alive_peak']:>5} {row['near80_peak']:>6} {row['projectile_peak']:>5} "
                  f"{row['zone_peak']:>5}")
    print("\n  how much of the B8 difficulty was the DRIVER, not the product:")
    for stage in stages:
        before, after = stats[(stage, "old")], stats[(stage, "new")]
        print(f"  stage {stage}: clear {before['clears']}/{before['runs']} -> {after['clears']}/{after['runs']}"
              f"   mean survival {before['mean_s']:.1f}s -> {after['mean_s']:.1f}s"
              f"   damage received {before['mean_damage']:.2f} -> {after['mean_damage']:.2f}"
              f"   hits/s {before['mean_hits_per_s']:.2f} -> {after['mean_hits_per_s']:.2f}"
              f"   damage/s {before['mean_damage_per_s']:.2f} -> {after['mean_damage_per_s']:.2f}")
    return stats


def ladder_verdict(stages, stats, label):
    print(f"\n### ladder verdict ({label} driver): is 22 not harder than 26 not harder than 29?")
    if len(stages) < 2:
        print("  need at least two stages")
        return True
    checks = [
        ("clear rate     (higher = easier)", lambda s: stats[(s, label)]["clear_rate"], True),
        ("mean survival  (higher = easier)", lambda s: stats[(s, label)]["mean_s"], True),
        ("hits/s         (higher = harder)", lambda s: stats[(s, label)]["mean_hits_per_s"], False),
        ("damage/s       (higher = harder)", lambda s: stats[(s, label)]["mean_damage_per_s"], False),
        ("damage received(higher = harder)", lambda s: stats[(s, label)]["mean_damage"], False),
    ]
    ok_all = True
    for title, getter, should_descend in checks:
        values = [getter(s) for s in stages]
        if should_descend:
            ordered = all(values[i] >= values[i + 1] for i in range(len(values) - 1))
            direction = "non-increasing"
        else:
            ordered = all(values[i] <= values[i + 1] for i in range(len(values) - 1))
            direction = "non-decreasing"
        ok_all = ok_all and ordered
        print(f"  {title:<34} {[round(v, 2) for v in values]}  {direction}: "
              f"{'HOLDS' if ordered else 'VIOLATED'}")
    print(f"  -> ladder {'HOLDS on every metric' if ok_all else 'is VIOLATED on at least one metric'}")
    return ok_all


def per_run(new, stages):
    print("\n### NEW driver, per run")
    for stage in stages:
        for row in sorted(new[stage], key=lambda r: r.get("seed", 0)):
            lethal = ((row.get("death_snapshot") or {}).get("lethal") or {})
            events = row.get("denial_events") or []
            print(f"  stage {stage} seed {row.get('seed')}: {row.get('outcome'):<9} "
                  f"{row.get('seconds', 0.0):>5.1f}s  hp_min {row.get('hp_min', 0):>6.2f}  "
                  f"dmg {row.get('damage_total', 0.0):>6.2f} in {row.get('hits_total', 0):>3} hits  "
                  f"killed by {lethal.get('tag', '-'):<14} "
                  f"denial {row.get('denial_samples', 0):>3} samples/{row.get('denial_streak_peak', 0):>2} streak "
                  f"{len(events)} events "
                  f"modes {row.get('denial_modes', [])}")
            print(f"      move {row.get('movement', 0.0):>7.0f}px  shots {row.get('shots', 0):>3}  "
                  f"dodge {row.get('dodge_decisions', 0):>3} decisions  "
                  f"all-danger {row.get('dodge_all_danger', 0):>3}  "
                  f"risky-choice {row.get('dodge_risky_choices', 0):>3}  "
                  f"wedged {row.get('dodge_all_blocked', 0):>2}")


def damage_table(old, new, stages):
    print("\n### damage taken by source: OLD driver vs NEW driver")
    old_rows = [r for s in stages for r in old[s]]
    new_rows = [r for s in stages for r in new[s]]
    old_totals, old_hits = category_totals(old_rows)
    new_totals, new_hits = category_totals(new_rows)
    old_grand = sum(old_totals.values()) or 1.0
    new_grand = sum(new_totals.values()) or 1.0
    keys = sorted(set(old_totals) | set(new_totals),
                  key=lambda k: -(old_totals.get(k, 0.0) + new_totals.get(k, 0.0)))
    print(f"{'source':<24} {'old dmg':>9} {'old %':>6} {'old hits':>8} "
          f"{'new dmg':>9} {'new %':>6} {'new hits':>8}")
    for key in keys:
        print(f"{key:<24} {old_totals.get(key, 0.0):>9.2f} {old_totals.get(key, 0.0) / old_grand * 100:>6.1f} "
              f"{old_hits.get(key, 0):>8} {new_totals.get(key, 0.0):>9.2f} "
              f"{new_totals.get(key, 0.0) / new_grand * 100:>6.1f} {new_hits.get(key, 0):>8}")
    print(f"{'TOTAL':<24} {old_grand:>9.2f} {100.0:>6.1f} {sum(old_hits.values()):>8} "
          f"{new_grand:>9.2f} {100.0:>6.1f} {sum(new_hits.values()):>8}")


def dodge_table(new, stages):
    print("\n### NEW driver dodge telemetry (the reaction-budget evidence)")
    print(f"{'stage':>5} {'decisions':>10} {'/run':>6} {'blocked':>8} {'scored':>8} "
          f"{'danger marks':>13} {'all-danger':>11} {'risky pick':>11} {'unchanged':>10} {'all-blocked':>12}")
    for stage in stages:
        rows = new[stage]
        stats = dodge_stats(rows)
        runs = max(1, len(rows))
        print(f"{stage:>5} {stats['dodge_decisions']:>10} {stats['dodge_decisions'] / runs:>6.0f} "
              f"{stats['dodge_blocked_candidates']:>8} {stats['dodge_scored_candidates']:>8} "
              f"{stats['dodge_danger_marks']:>13} {stats['dodge_all_danger']:>11} "
              f"{stats['dodge_risky_choices']:>11} {stats['dodge_unchanged']:>10} "
              f"{stats['dodge_all_blocked']:>12}")
    totals = dodge_stats([r for s in stages for r in new[s]])
    decided = max(1, totals["dodge_decisions"])
    scored = max(1, totals["dodge_scored_candidates"])
    print(f"  decisions are 10 Hz by construction (bot_clock gate), so the bot cannot out-react a")
    print(f"  person: {totals['dodge_decisions']} decisions over the batch.")
    print(f"  rejected-danger candidates: {totals['dodge_danger_marks']} danger marks across "
          f"{scored} scored candidates ({totals['dodge_danger_marks'] / scored * 100:.0f}% of candidates "
          f"were inside a live footprint).")
    print(f"  emergency all-directions-danger decisions: {totals['dodge_all_danger']} "
          f"({totals['dodge_all_danger'] / decided * 100:.1f}% of decisions) - survived by taking the "
          f"shallowest exit.")
    print(f"  decisions where the chosen direction was still inside a footprint: "
          f"{totals['dodge_risky_choices']}")
    print(f"  decisions where nothing constrained the wish (kept verbatim): {totals['dodge_unchanged']}")
    print(f"  decisions where all 16 samples were wall-blocked (wedged): {totals['dodge_all_blocked']}")


def escape_table(new, stages):
    print("\n### unavoidable-overlap check on the NEW driver (ordinary stages)")
    for stage in stages:
        for row in new[stage]:
            events = row.get("denial_events") or []
            print(f"  stage {stage} seed {row.get('seed')}: {row.get('outcome'):<9} "
                  f"{row.get('seconds', 0.0):>5.1f}s  fair-denial samples {row.get('denial_samples', 0):>3} "
                  f"longest streak {row.get('denial_streak_peak', 0):>2}  events {len(events)} "
                  f"modes {row.get('denial_modes', [])}")


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 1
    old_base, new_base, old_tag, new_tag = sys.argv[1:5]
    stages = [int(a) for a in sys.argv[5:]] or [22, 26, 29]
    old_rows = {s: read_batch(old_base, old_tag, s) for s in stages}
    new_rows = {s: read_batch(new_base, new_tag, s) for s in stages}
    old = {s: group_stats(old_rows[s]) for s in stages}
    new = {s: group_stats(new_rows[s]) for s in stages}
    missing = [s for s in stages if not old[s]["runs"] or not new[s]["runs"]]
    if missing:
        print(f"  missing evidence for stages {missing}")
    stats = difficulty_table(stages, old, new)
    print("\n### B8 ladder, for reference (what the old driver measured)")
    ladder_verdict(stages, stats, "old")
    print("\n### B9 ladder, on the new driver (the one this round is judged on)")
    holds = ladder_verdict(stages, stats, "new")
    per_run(new_rows, stages)
    damage_table(old_rows, new_rows, stages)
    dodge_table(new_rows, stages)
    escape_table(new_rows, stages)
    payload = {
        "stages": stages,
        "old_tag": old_tag,
        "new_tag": new_tag,
        "old": {str(s): old[s] for s in stages},
        "new": {str(s): new[s] for s in stages},
        "new_dodge": {str(s): dodge_stats(new_rows[s]) for s in stages},
        "ladder_holds_new_driver": holds,
    }
    out = os.path.join(new_base, "summary.json")
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent="\t")
    print(f"\n  wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
