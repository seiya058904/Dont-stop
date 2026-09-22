"""Post-run statistics only: never runs in a measured fight."""
import bisect
import json
import math
import sys
from pathlib import Path


def stats(values):
    if not values:
        return None
    values = [float(v) for v in values]
    ordered = sorted(values)
    n = len(ordered)

    def percentile(q):
        return ordered[min(n - 1, max(0, math.ceil(n * q) - 1))]

    over16_67 = sum(v > 16.67 for v in ordered)
    over25 = sum(v > 25 for v in ordered)
    over33 = sum(v > 33 for v in ordered)
    over50 = sum(v > 50 for v in ordered)
    over100 = sum(v > 100 for v in ordered)
    return {
        "frames": n,
        "avg": sum(ordered) / n,
        "p50": percentile(.50),
        "p95": percentile(.95),
        "p99": percentile(.99),
        "max": ordered[-1],
        "over16_67": over16_67,
        "over25": over25,
        "over33": over33,
        "over33_percent": 100 * over33 / n,
        "over50": over50,
        "over100": over100,
        "over250": sum(v > 250 for v in ordered),
        "over1000": sum(v > 1000 for v in ordered),
    }


def _weights(rows, hz, duration, relative_ticks=False):
    if not rows:
        return []
    origin = rows[0].get("tick", 0) if relative_ticks else 0
    weights = []
    for index, row in enumerate(rows):
        current = float(row.get("tick", 0)) - float(origin)
        if index + 1 < len(rows):
            next_tick = float(rows[index + 1].get("tick", 0)) - float(origin)
            weights.append(max(0.0, (next_tick - current) / hz))
        else:
            weights.append(max(0.0, duration - current / hz))
    return weights


def _weighted(rows, weights, key):
    total = sum(weights)
    return sum(float(row.get(key, 0)) * weight for row, weight in zip(rows, weights)) / total if total else None


def _pressure_spike_rank(contexts):
    ranked = []
    for rank, context in enumerate(sorted(contexts, key=lambda row: float(row.get("ms", 0)), reverse=True)[:20], 1):
        causes = []
        # Births/free are explicitly TEST_FIXTURE events. They must not be mistaken for a product
        # regression when this list is used to choose the next engineering experiment.
        if context.get("spawn_count", 0):
            causes.append("TEST_FIXTURE:enemy_spawn")
        if context.get("projectile_spawn", 0):
            causes.append("TEST_FIXTURE:projectile_spawn")
        if context.get("death_free_count", 0):
            causes.append("death_or_free")
        if context.get("boss_present"):
            causes.append("boss")
        if context.get("path_requests", 0):
            causes.append("pathfinding")
        if context.get("physics_contacts", 0):
            causes.append("physics_contacts")
        if context.get("fog_entries", 0):
            causes.append("fog")
        if context.get("vfx_created", 0):
            causes.append("vfx_counter_active")
        if context.get("audio_players", 0):
            causes.append("audio_players_active")
        if not causes:
            causes.append("unclassified_runtime")
        ranked.append({"rank": rank, "ms": context.get("ms"), "phase": context.get("phase"),
                       "candidate_causes": causes, "context": context})
    return ranked


def summarize(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    raw = data.get("raw_frames")
    if not raw:
        return {"file": path.name, "missing_raw": True}

    workload = raw.get("workload_scenario")
    is_pressure = workload == "P"
    pressure = raw.get("pressure") or {}
    if is_pressure and not pressure and raw.get("steady_ms") is not None:
        pressure = raw

    all_ms = [float(value) for value in raw.get("ms", [])]
    all_ts = [float(value) for value in raw.get("combat_wall_seconds", [])]
    phase = pressure.get("frame_phase", [])
    steady_values = [float(value) for value in pressure.get("steady_ms", [])]
    if is_pressure and steady_values:
        # The steady array is authoritative for percentiles. Use the matching original frame
        # timestamps only for the optional hot-window view, and use the last steady segment when
        # a target shortfall forced the fixture back into load-build.
        steady_indices = [index for index, value in enumerate(phase) if value == "steady"]
        if len(steady_indices) >= len(steady_values) and len(all_ts) >= len(phase):
            selected = steady_indices[-len(steady_values):]
            ms = steady_values
            ts = [all_ts[index] for index in selected]
        else:
            ms = steady_values
            duration = float(pressure.get("steady_seconds", 0) or 0)
            ts = [duration * index / max(1, len(ms) - 1) for index in range(len(ms))]
    else:
        ms = all_ms
        ts = all_ts

    analysis_ts = ts
    if is_pressure and ts:
        start = ts[0]
        analysis_ts = [value - start for value in ts]

    hot = [value for value, timestamp in zip(ms, analysis_ts) if timestamp >= 5] if not is_pressure else ms[:]
    window = []
    left = 0
    worst = None
    for right, (timestamp, value) in enumerate(zip(analysis_ts, ms)):
        bisect.insort(window, value)
        while left <= right and analysis_ts[left] < timestamp - 5:
            window.pop(bisect.bisect_left(window, ms[left]))
            left += 1
        if timestamp >= 5 and window:
            window_p95 = window[math.ceil(len(window) * .95) - 1]
            if worst is None or window_p95 > worst["p95"]:
                worst = {"from_s": timestamp - 5, "to_s": timestamp, **stats(window)}

    longest = 0.0
    run = 0.0
    for value in ms:
        run = run + value if value > 33.3 else 0.0
        longest = max(longest, run)

    all_rows = raw.get("load_samples", [])
    if is_pressure:
        rows = [row for row in all_rows if row.get("pressure_phase") == "steady"]
        if not rows:
            rows = all_rows
        hz = float(raw.get("physics_hz", 60))
        sim = float(pressure.get("steady_seconds", 0) or 0)
        if sim <= 0 and ms:
            sim = float(len(ms)) / hz
        weights = _weights(rows, hz, sim, relative_ticks=True)
    else:
        rows = all_rows
        hz = float(raw.get("physics_hz", 60))
        sim = float(raw.get("effective_sim_seconds", 0))
        weights = _weights(rows, hz, sim, relative_ticks=False)

    wall = float(pressure.get("steady_seconds", 0) or 0) if is_pressure else float(
        raw.get("measured_wall_s", analysis_ts[-1] if analysis_ts else 0)
    ) - float(raw.get("paused_ms", 0)) / 1000
    full = stats(ms)
    hot_stats = stats(hot)
    build_stats = stats(pressure.get("load_build_ms", [])) if is_pressure else None
    settling_stats = stats(pressure.get("settling_ms", [])) if is_pressure else None
    steady_stats = stats(steady_values) if is_pressure else None

    stage = next(iter(raw.get("round_contexts", [])), {}).get("stage")
    required_seconds = 150 if stage == 40 else (15 if is_pressure else 45)
    pressure_valid = bool(pressure.get("pressure_measurement_valid", raw.get("pressure_measurement_valid", False))) if is_pressure else True
    duration_observed = (
        pressure_valid and float(pressure.get("steady_seconds", 0) or 0) >= required_seconds
        if is_pressure else
        ((raw.get("boss_complete") and not raw.get("controlled_boss")) if stage == 40 else sim >= required_seconds)
    )
    formal = raw.get("mode") == "formal" and raw.get("requested_seconds", 0) >= required_seconds and duration_observed
    sim_seconds = float(pressure.get("steady_sim_seconds", sim) or sim) if is_pressure else sim
    sim_wall = sim_seconds / wall if wall else None

    if is_pressure:
        simultaneous = {
            "steady_samples": int(pressure.get("steady_samples", len(steady_values)) or 0),
            "target_met_frames": int(pressure.get("steady_target_frames", 0) or 0),
            "shortfall_frames": int(pressure.get("steady_shortfall_frames", 0) or 0),
            "observed_sim_s": float(pressure.get("steady_seconds", 0) or 0),
            "pressure_measurement_valid": pressure_valid,
            "method": "per-frame steady phase after both live counters reached 180; build and settling excluded",
        }
    else:
        simultaneous = {}
        for key in ("alive", "drawing", "on_screen"):
            flag = "simultaneous_180_" + key
            simultaneous[key + "_observed_sim_s"] = sum(
                max(0, (float(b.get("tick", 0)) - float(a.get("tick", 0))) / hz)
                for a, b in zip(rows, rows[1:])
                if a.get("round") == b.get("round") and a.get(flag) and b.get(flag)
            )
        simultaneous["method"] = "adjacent 100ms gauge samples both meet 180+180; sampled coverage, not continuous proof"

    timing_pass = bool(
        formal and full and full["p95"] <= 18.5 and full["p99"] <= 25 and
        full["over33_percent"] < .5 and wall > 0 and sim_wall is not None and sim_wall >= .98
    )
    context = pressure.get("spike_context", []) if is_pressure else []
    return {
        "file": path.name,
        "full": full,
        "first5": stats([value for value, timestamp in zip(ms, analysis_ts) if timestamp < 5]),
        "hot": hot_stats,
        "worst5": worst,
        "longest_over33_ms": longest,
        "sim_s": sim,
        "wall_s": wall,
        "sim_wall": sim_wall,
        "mode": raw.get("mode", "legacy-unclassified"),
        "formal_duration_met": formal,
        "simultaneous_180": simultaneous,
        "load_build": build_stats,
        "settling": settling_stats,
        "steady": steady_stats,
        "pressure": pressure,
        "steady_ms_source": "pressure.steady_ms" if is_pressure else "raw_frames.ms",
        "long_frames": raw.get("long_frames", []),
        "timing_pass": timing_pass,
        "unclassified_over50": [{"wall_s": timestamp, "ms": value} for value, timestamp in zip(ms, analysis_ts) if value > 50],
        "pressure_spike_rank": _pressure_spike_rank(context),
        "load": {
            "weighted_ordinary": _weighted(rows, weights, "ordinary"),
            "weighted_elite": _weighted(rows, weights, "elite"),
            "weighted_visible": _weighted(rows, weights, "visible"),
            "weighted_shots": _weighted(rows, weights, "shots_live"),
            "shots_peak": max((row.get("shots_live", 0) for row in rows), default=0),
            "near_cap_sim_percent": (
                100 * sum(weight for row, weight in zip(rows, weights)
                          if row.get("shots_live", 0) >= (180 if is_pressure else 162)) / sum(weights)
                if sum(weights) else 0
            ),
            "last": rows[-1] if rows else {},
        },
        "boss_complete": raw.get("boss_complete"),
        "timeout": raw.get("measurement_timeout"),
        "errors": data.get("errors", data.get("diagnostics", [])),
        "surface": raw.get("surface"),
        "build": data.get("build"),
    }


if __name__ == "__main__":
    print(json.dumps([summarize(Path(path)) for path in sys.argv[1:]], ensure_ascii=False, indent=2))
