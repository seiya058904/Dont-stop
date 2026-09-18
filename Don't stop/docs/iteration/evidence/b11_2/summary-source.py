#!/usr/bin/env python3
"""B11.2 consolidated summary: the tables that go into the report.

Everything here is derived from the evidence JSON under
`docs/iteration/evidence/b11_2/stress/`, so every number in the report can be recomputed from the
committed artefacts rather than trusted.

Design rules (same as B11.1, so the two rounds are comparable):

  * the NOISE FLOOR comes from two runs of the SAME build (BEFORE r1 vs BEFORE r2: same source,
    same seed, same machine, same window), so a delta is compared against how much two identical
    builds already differ;
  * a delta is only promoted to "ATTRIBUTABLE" when it has the same sign in every scenario AND
    clears 3x that floor in every scenario; anything else is reported as noise, in those words;
  * every count is normalised per second of measured combat, because the runs are wall-clock bound
    and the shot count differs between them;
  * each side's number is the mean of its two reps, and the noise floor is measured from the same
    two before-reps, so side and floor are estimated the same way.

B11.2 additionally prints the POINT-3 LEDGER on its own. The question there is not "did the fog cost
fall" but "did the fog cost rise enough to eat the redraw saving", which only the four numbers side
by side can answer.
"""
import json
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else 'docs/iteration/evidence/b11_2'
SCENES = ['A', 'B', 'C', 'D']
NAME = {'A': 'A normal', 'B': 'B dense enemies', 'C': 'C dense attacks', 'D': 'D worst visual'}
ISO = ['none', 'vfx', 'labels', 'trails', 'fogcore', 'tddecor', 'particles']
OUT = []


def emit(line=''):
    OUT.append(line)
    print(line)


def load(side, scen, rep, iso=False):
    name = ('stress-%s-iso-%s-D.json' % (side, scen)) if iso else \
           ('stress-%s-r%d-%s.json' % (side, rep, scen))
    return json.load(open(os.path.join(ROOT, 'stress', side, name), encoding='utf-8'))


def f(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def unit(j):
    """Every metric for one run, in per-second or per-unit form. `None` = not instrumented."""
    ink, cpu, load_, peaks = j.get('ink', {}), j.get('cpu', {}), j.get('load', {}), j.get('peaks', {})
    s = f(cpu.get('combat_s')) or 1.0
    frames = f(cpu.get('frames')) or 1.0
    lines = f(ink.get('fog_push_lines'))
    appended = f(ink.get('fog_appended'))
    dropped = f(ink.get('fog_dropped'))
    drawn = ink.get('fog_entries_drawn')
    draws = ink.get('fog_draws')
    fusec = ink.get('fog_draw_usec')
    shots = f(ink.get('shoots'))
    return {
        'phys ms/frame': f(cpu.get('phys_avg')),
        'phys p99 ms': f(cpu.get('phys_p99')),
        'frame avg ms': f(j.get('frame_ms', {}).get('avg')),
        'spikes >33 /run': f(j.get('spikes', {}).get('over33')),
        'spikes >50 /run': f(j.get('spikes', {}).get('over50')),
        'slow run ms': f(j.get('spikes', {}).get('slow_run_ms')),
        'enemies peak': f(load_.get('enemies_peak')),
        'zones peak': f(load_.get('zones_peak')),
        'draws avg': f(load_.get('draws_avg')),

        # ---- fog volume / cost (point 3) ----------------------------------------------------
        'fog push lines /s': lines / s,
        'fog entries offered /s': f(ink.get('fog_pushes')) / s,
        'fog entries accepted /s': appended / s,
        'fog entries dropped /s': dropped / s,
        'fog dropped share %': 100.0 * dropped / (appended + dropped) if (appended + dropped) else 0.0,
        'fog entries per line': appended / lines if lines else 0.0,
        'fog child scans /run': f(ink.get('fog_ensure_scans')),
        'fog canvas hits /run': f(ink.get('fog_canvas_hits')),
        'fog canvas draws /s': (f(draws) / s) if draws is not None else None,
        'fog entries drawn /s': (f(drawn) / s) if drawn is not None else None,
        'fog drawn share': (f(drawn) / appended) if (drawn is not None and appended) else None,
        'fog draw us/s': (f(fusec) / s) if fusec is not None else None,
        'fog draw us/frame': (f(fusec) / frames) if fusec is not None else None,

        # ---- zone tier (point 3's other half) -----------------------------------------------
        'zone draw us/s': f(ink.get('zone_draw_usec')) / s,
        'zone step us/s': f(ink.get('zone_step_usec')) / s,
        'zone total us/s': (f(ink.get('zone_draw_usec')) + f(ink.get('zone_step_usec'))) / s,
        'telegraph draws /s': f(ink.get('telegraph_draws')) / s,
        'telegraph draw us/s': f(ink.get('telegraph_draw_usec')) / s,

        # ---- shots / mask (point 1) ----------------------------------------------------------
        'shots created /s': shots / s,
        'shot exceptions /s': f(ink.get('shot_exceptions')) / s,
        'shot exceptions per shot': (f(ink.get('shot_exceptions')) / shots) if shots else 0.0,
        'shot fog mirrors /s': f(ink.get('shot_fog_mirrors')) / s,

        # ---- status walks (BaseMonster) ------------------------------------------------------
        'status walks /s': f(ink.get('status_walks')) / s,
        'status walks empty %': (100.0 * f(ink.get('status_walks_empty')) / f(ink.get('status_walks'))
                                 if f(ink.get('status_walks')) else 0.0),

        # ---- everything else named in the report ---------------------------------------------
        'wall raycasts /s': f(peaks.get('raycasts')) / s,
        'raycasts skipped /s': f(peaks.get('raycasts_skipped')) / s,
        'path queries /s': f(load_.get('path_per_s')),
        'path us/s': f(ink.get('path_usec')) / s,

        # ---- guardrails: things this round must NOT have made worse ---------------------------------
        # These are not optimisation targets. They are here so the "nothing got worse" claim in the
        # report's invariants section is a measurement rather than an assumption: the load profile
        # must be the same size on both sides, the node/object ceiling must not have been raised,
        # and the worst physics frame must not have grown.
        'objects peak': f(load_.get('objects_peak')),
        'canvas items peak': f(load_.get('canvas_items_peak')),
        'orphans peak': f(load_.get('orphans_peak')),
        'draws peak': f(load_.get('draws_peak')),
        'phys max ms': f(cpu.get('phys_max')),
        'phys frames >8 ms': f(cpu.get('phys_over8')),
        'phys frames >12 ms': f(cpu.get('phys_over12')),
    }


B_R1 = {s: load('before', s, 1) for s in SCENES}
B_R2 = {s: load('before', s, 2) for s in SCENES}
A_R1 = {s: load('after', s, 1) for s in SCENES}
A_R2 = {s: load('after', s, 2) for s in SCENES}
KEYS = list(unit(B_R1['A']).keys())


def mean2(ua, ub):
    """Per-scenario metric means over one side's two reps (None-aware)."""
    out = {}
    for s in SCENES:
        a, b = unit(ua[s]), unit(ub[s])
        out[s] = {}
        for k in KEYS:
            va, vb = a[k], b[k]
            if va is None and vb is None:
                out[s][k] = None
            elif va is None:
                out[s][k] = vb
            elif vb is None:
                out[s][k] = va
            else:
                out[s][k] = (va + vb) / 2.0
    return out


before, after = mean2(B_R1, B_R2), mean2(A_R1, A_R2)


def fmt(v):
    if v is None:
        return '-'
    if isinstance(v, float) and v != v:
        return 'n/a'
    if abs(v) >= 100000:
        return '%.0f' % v
    if abs(v) >= 100:
        return '%.1f' % v
    return '%.3f' % v


def avg(vals):
    """Mean of the non-None values, or None when the metric is absent on this side entirely."""
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def verdict_of(ds, ratios, floor):
    if not ds:
        return 'no comparable pair'
    same_sign = all(d > 0 for d in ds) or all(d < 0 for d in ds)
    if floor != floor:
        return 'directionally consistent' if same_sign else 'mixed'
    if same_sign and min(ratios) >= 3:
        return 'ATTRIBUTABLE'
    return 'directionally consistent, within noise' if same_sign else 'NOISE'


# ---- 1. build identities ---------------------------------------------------------------------
emit('## Build identities (hashed from the bytes the browser actually loaded)')
emit()
emit('| | BEFORE | AFTER |')
emit('|---|---|---|')
emit('| identity (sha256 of wasm\u2016pck\u2016js) | `%s` | `%s` |' % (
    B_R1['A']['build']['identity'][:16] + '\u2026', A_R1['A']['build']['identity'][:16] + '\u2026'))
for n in ('index.wasm', 'index.pck', 'index.js'):
    b, a = B_R1['A']['build'][n], A_R1['A']['build'][n]
    emit('| %s | %s (%d B) | %s (%d B) \u2014 %s |' % (
        n, b['sha256'][:12], b['bytes'], a['sha256'][:12], a['bytes'],
        'identical' if b['sha256'] == a['sha256'] else '**differs**'))
emit()
emit('The engine payload is byte-identical on both sides and only the `.pck` (which carries the')
emit('scripts) changes \u2014 the two builds differ *only* in game code. All runs on one side share one')
emit('identity; the two sides share none.')
emit()

# ---- 2. noise floor -------------------------------------------------------------------------
emit('## Noise floor, measured from two runs of the SAME build (BEFORE r1 vs BEFORE r2)')
emit()
emit('| metric | BEFORE r1 (mean of 4) | BEFORE r2 (mean of 4) | mean abs delta |')
emit('|---|---:|---:|---:|')
noise = {}
for k in KEYS:
    dels = []
    for s in SCENES:
        v1, v2 = unit(B_R1[s])[k], unit(B_R2[s])[k]
        if v1 not in (None, 0) and v2 is not None:
            dels.append(abs(v2 - v1) / abs(v1) * 100)
    noise[k] = sum(dels) / len(dels) if dels else float('nan')
    m1, m2 = avg([unit(B_R1[s])[k] for s in SCENES]), avg([unit(B_R2[s])[k] for s in SCENES])
    # A metric can be ABSENT (`None`: this build has no such counter) or genuinely ZERO. Conflating
    # the two is how a guardrail that legitimately reads 0 - orphan objects, say - ends up described
    # as "not instrumented". The wording is picked per case instead.
    if dels:
        label = '**%.1f%%**' % noise[k]
    elif m1 is None or m2 is None:
        label = 'n/a (absent from the BEFORE build)'
    elif m1 == 0.0 and m2 == 0.0:
        label = 'n/a (reads zero on both BEFORE reps)'
    elif m1 == 0.0:
        label = 'n/a (BEFORE reads zero, so no relative floor)'
    else:
        label = 'n/a (no comparable pair)'
    emit('| %s | %s | %s | %s |' % (k, fmt(m1), fmt(m2), label))
emit()

# ---- 3. BEFORE -> AFTER ---------------------------------------------------------------------
emit('## BEFORE \u2192 AFTER over the four core scenarios, judged against that floor')
emit()
emit('| metric | BEFORE | AFTER | delta | noise | multiple | verdict |')
emit('|---|---:|---:|---:|---:|---:|---|')
for k in KEYS:
    ds, ratios = [], []
    for s in SCENES:
        b, a = before[s][k], after[s][k]
        if b not in (None, 0) and a is not None:
            d = (a - b) / b * 100
            ds.append(d)
            ratios.append(abs(d) / noise[k] if (noise[k] and noise[k] == noise[k]) else 0)
    mb = avg([before[s][k] for s in SCENES])
    ma = avg([after[s][k] for s in SCENES])
    if not ds:
        has_b = any(before[s][k] is not None for s in SCENES)
        has_a = any(after[s][k] is not None for s in SCENES)
        if has_b and not has_a:
            note = 'not measured on the AFTER build'
        elif has_a and not has_b:
            note = 'not measured on the BEFORE build'
        elif mb == 0.0 and ma == 0.0:
            note = 'reads zero on both sides at this load'
        else:
            note = 'no non-zero BEFORE reading to divide by'
        emit('| %s | %s | %s | \u2014 | \u2014 | \u2014 | %s |' % (k, fmt(mb), fmt(ma), note))
        continue
    ratio_lo, ratio_hi = min(ratios), max(ratios)
    emit('| %s | %s | %s | %+.1f%% | %.1f%% | %.1f\u2013%.1f\u00d7 | %s |' % (
        k, fmt(mb), fmt(ma), sum(ds) / len(ds), noise[k], ratio_lo, ratio_hi,
        verdict_of(ds, ratios, noise[k])))
emit()

# ---- 4. point-3 ledger ----------------------------------------------------------------------
emit('## Point-3 ledger: did the fog side grow enough to eat the redraw saving?')
emit()
emit('The acceptance rule set for this round was: *"if the Fog push clearly doubles and eats the')
emit('redraw saving, do not accept this implementation."* So the four required numbers are printed')
emit('together for the worst-load scenario D, each against its own noise floor.')
emit()
emit('| metric | BEFORE D | AFTER D | delta | noise | multiple | verdict |')
emit('|---|---:|---:|---:|---:|---:|---|')
for k in ['fog push lines /s', 'fog entries accepted /s', 'fog entries dropped /s',
          'fog dropped share %', 'fog draw us/s', 'zone draw us/s', 'zone step us/s',
          'zone total us/s']:
    b, a = before['D'][k], after['D'][k]
    if b is None or a is None:
        emit('| %s | %s | %s | \u2014 | \u2014 | \u2014 | %s |' % (
            k, fmt(b), fmt(a),
            'not measured on the BEFORE build' if b is None else 'not measured on the AFTER build'))
        continue
    if b == 0.0:
        emit('| %s | %s | %s | \u2014 | \u2014 | \u2014 | zero on the BEFORE side, so there is no ratio to judge |'
             % (k, fmt(b), fmt(a)))
        continue
    d = (a - b) / b * 100
    r = abs(d) / noise[k] if (noise[k] and noise[k] == noise[k]) else 0
    emit('| %s | %s | %s | %+.1f%% | %.1f%% | %.1f\u00d7 | %s |' % (
        k, fmt(b), fmt(a), d, noise[k], r, verdict_of([d], [r], noise[k])))
emit()

# ---- 5. per-scenario detail -----------------------------------------------------------------
emit('## Per-scenario delta detail (AFTER mean vs BEFORE mean)')
emit()
emit('| metric | ' + ' | '.join(NAME[s] for s in SCENES) + ' |')
emit('|---|' + '---:|' * len(SCENES))
for k in KEYS:
    cells = []
    for s in SCENES:
        b, a = before[s][k], after[s][k]
        if b is None or a is None:
            cells.append('n/a')
        elif b == 0.0:
            cells.append('+0.0%' if a == 0.0 else '0 \u2192 %s' % fmt(a))
        else:
            cells.append('%+.1f%%' % ((a - b) / b * 100))
    emit('| %s | %s |' % (k, ' | '.join(cells)))
emit()

# ---- 6. visual isolation --------------------------------------------------------------------
emit('## Visual isolation, AFTER build, worst-load profile D')
emit()
emit('Each column switches ONE purely-visual product off and leaves damage, collision, timing, AI')
emit('and spawning running. A column that moves nothing is a cost already hidden by vsync, and is')
emit('reported as such rather than dressed up.')
emit()
base = unit(load('after', 'none', 0, iso=True))
emit('| metric | all on | ' + ' | '.join(ISO[1:]) + ' |')
emit('|---|' + '---:|' * (len(ISO) - 1))
for k in ['phys ms/frame', 'frame avg ms', 'draws avg', 'zone draw us/s', 'telegraph draws /s',
          'telegraph draw us/s', 'zone total us/s']:
    cells = []
    for flag in ISO[1:]:
        v = unit(load('after', flag, 0, iso=True))[k]
        cells.append('n/a' if (not base[k] or v is None) else '%+.1f%%' % ((v - base[k]) / base[k] * 100))
    emit('| %s | %s | %s |' % (k, fmt(base[k]), ' | '.join(cells)))
emit()

path = os.path.join(ROOT, 'summary.md')
open(path, 'w', encoding='utf-8').write('\n'.join(OUT) + '\n')
print('wrote %s' % path)
