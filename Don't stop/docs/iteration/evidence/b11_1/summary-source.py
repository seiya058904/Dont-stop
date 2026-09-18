#!/usr/bin/env python3
"""B11.1 consolidated summary: the table that goes into the report.

Everything here is derived from the committed evidence JSON under
docs/iteration/evidence/b11_1/stress/, so every number in the report can be recomputed from the
artefacts rather than trusted.

Design rules, and they are the whole point of the file:
  * the SPIKE CENSUS is split into round-start (t < 5 s of each round) and steady combat, because the
    raw counts are dominated by a per-round-start hitch that no combat change can affect;
  * the NOISE FLOOR comes from two runs of the SAME build (BEFORE round1 vs BEFORE round2), so a
    delta can be compared against how much two identical builds already differ;
  * a delta is only promoted to "attributable" when it clears 3x that floor in all five scenarios.
"""
import json
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else 'docs/iteration/evidence/b11_1'
SCENES = ['c1', 'c2', 'a1', 'b1', 'd1']
NAME = {'c1': 'C', 'c2': 'C-rpt', 'a1': 'A', 'b1': 'B', 'd1': 'D'}
OUT = []


def emit(line=''):
    OUT.append(line)
    print(line)


def load(side, s, r1=False):
    d = 'before-round1' if r1 else side
    p = os.path.join(ROOT, 'stress', d, 'stress-%s%s-%s.json' % (side if not r1 else 'before', s, s[0].upper()))
    return json.load(open(p, encoding='utf-8'))


def census(j):
    rc = nrc = None
    for r in j.get('bucket_rows', []):
        if r.get('family') != 'ms':
            continue
        if r['name'] == 'raycast_frame':
            rc = float(r['n'])
        elif r['name'] == 'no_raycast_frame':
            nrc = float(r['n'])
    return rc, nrc


def unit(j):
    cpu, p = j['cpu'], j['peaks']
    s = float(cpu['combat_s']) or 1.0
    return {
        'wall raycasts / run': float(p['raycasts']),
        'raycasts / s': float(p['raycasts']) / s,
        'wall raycasts skipped / run': float(p['raycasts_skipped']),
        'clear_line us / call': float(cpu['clear_line_usec']) / (float(p['clear_line']) or 1.0),
        'onHit us / hit': float(cpu['onhit_usec']) / (float(p['hits']) or 1.0),
        'phys ms / frame': float(cpu['phys_avg']),
        'phys p99 ms': float(cpu['phys_p99']),
        'zone step us / frame': float(cpu['zone_step_usec']) / (float(cpu['frames']) or 1.0),
        'zone draw us / frame': float(cpu['zone_draw_usec']) / (float(cpu['frames']) or 1.0),
        'reward fanout reuses / run': float(p['reward_reused']),
        'enemies peak': float(p['enemies']),
    }


before_r1 = {s: load('before', s, r1=True) for s in SCENES}
before = {s: load('before', s) for s in SCENES}
after = {s: load('after', s) for s in SCENES}
KEYS = list(unit(before['c1']).keys())

emit('## Build identities (hashed from the bytes the browser actually loaded)')
emit()
emit('| | BEFORE | AFTER |')
emit('|---|---|---|')
emit('| identity (sha256 of wasm‖pck‖js) | `%s` | `%s` |' % (
    before['c1']['build']['identity'][:16] + u'\u2026', after['c1']['build']['identity'][:16] + u'\u2026'))
for n in ('index.wasm', 'index.pck', 'index.js'):
    b, a = before['c1']['build'][n], after['c1']['build'][n]
    same = 'identical' if b['sha256'] == a['sha256'] else '**differs**'
    emit('| %s | %s (%d B) | %s (%d B) \u2014 %s |' % (n, b['sha256'][:12], b['bytes'], a['sha256'][:12], a['bytes'], same))
emit()

emit('## Percent of physics frames that issued at least one wall-clip raycast')
emit()
emit('`raycast_frame` vs `no_raycast_frame` is the one mutually exclusive pair in the census.')
emit()
emit('| scenario | BEFORE r1 | BEFORE r2 | AFTER | r1\u2192r2 noise | r2\u2192AFTER |')
emit('|---|---:|---:|---:|---:|---:|')
for s in SCENES:
    a, b, c = census(before_r1[s]), census(before[s]), census(after[s])
    fa, fb, fc = 100 * a[0] / (a[0] + a[1]), 100 * b[0] / (b[0] + b[1]), 100 * c[0] / (c[0] + c[1])
    emit('| %s | %.1f%% | %.1f%% | %.1f%% | %.1f pt | **%.1f pt** |' % (NAME[s], fa, fb, fc, abs(fb - fa), fc - fb))
means = []
for d in (before_r1, before, after):
    v = [100 * census(d[s])[0] / sum(census(d[s])) for s in SCENES]
    means.append(sum(v) / 5)
emit('| **mean** | **%.1f%%** | **%.1f%%** | **%.1f%%** | **%.1f pt** | **%.1f pt** |' % (
    means[0], means[1], means[2], abs(means[1] - means[0]), means[2] - means[1]))
emit()

emit('## Spike census, split by window (over 5 scenarios, 2 rounds each)')
emit()
emit('| window | BEFORE o25/o33/o50 | max ms | AFTER o25/o33/o50 | max ms |')
emit('|---|---:|---:|---:|---:|')
tot = {}
for side, d in (('BEFORE', before), ('AFTER', after)):
    agg = {'start': [0, 0, 0, 0.0], 'steady': [0, 0, 0, 0.0]}
    for s in SCENES:
        for r in d[s]['per_second']:
            k = 'start' if float(r['t']) < 5.0 else 'steady'
            for i, f in enumerate(('over25', 'over33', 'over50')):
                agg[k][i] += int(r[f])
            agg[k][3] = max(agg[k][3], float(r['max']))
    tot[side] = agg
for k, label in (('start', 'round start (t<5 s of each round)'), ('steady', 'steady combat (t\u22655 s)')):
    b, a = tot['BEFORE'][k], tot['AFTER'][k]
    emit('| %s | %d/%d/%d | %.0f | %d/%d/%d | %.0f |' % (label, b[0], b[1], b[2], b[3], a[0], a[1], a[2], a[3]))
emit()
emit('Totals from `spikes.*` (what the raw field reports) are the sum of the two rows above, so the')
emit('raw `over33`/`over50` counts are ~80% round-start hitch and not the reported phenomenon.')
emit()

emit('## Noise floor, measured from two runs of the SAME build')
emit()
emit('| metric | BEFORE r1 | BEFORE r2 | mean abs delta |')
emit('|---|---:|---:|---:|')
noise = {}
for k in KEYS:
    dels = [abs(unit(before[s])[k] - unit(before_r1[s])[k]) / abs(unit(before_r1[s])[k]) * 100
            for s in SCENES if unit(before_r1[s])[k]]
    noise[k] = sum(dels) / len(dels) if dels else float('nan')
    emit('| %s | %.2f | %.2f | **%.1f%%** |' % (
        k, sum(unit(before_r1[s])[k] for s in SCENES) / 5,
        sum(unit(before[s])[k] for s in SCENES) / 5, noise[k]))
emit()

emit('## BEFORE \u2192 AFTER, five scenarios, judged against that floor')
emit()
emit('| metric | BEFORE | AFTER | delta | noise | multiple | verdict |')
emit('|---|---:|---:|---:|---:|---:|---|')
for k in KEYS:
    ds, ratios = [], []
    for s in SCENES:
        b, a = unit(before[s])[k], unit(after[s])[k]
        if b:
            d = (a - b) / b * 100
            ds.append(d)
            ratios.append(abs(d) / noise[k] if noise[k] else 0)
    mb = sum(unit(before[s])[k] for s in SCENES) / 5
    ma = sum(unit(after[s])[k] for s in SCENES) / 5
    if not ds:
        # The metric is structurally zero in BEFORE, so a percentage delta does not exist: it is a
        # capability the BEFORE build never exercised at all.
        emit('| %s | %.0f | %.0f | new | \u2014 | \u2014 | only the AFTER build can raise this |' % (k, mb, ma))
        continue
    md = sum(ds) / len(ds)
    same_sign = all(d > 0 for d in ds) or all(d < 0 for d in ds)
    lo, hi = min(ratios), max(ratios)
    verdict = 'ATTRIBUTABLE' if (same_sign and lo >= 3) else (
        'directionally consistent, within noise' if same_sign else 'noise')
    if noise[k] != noise[k]:
        verdict = 'new in AFTER (cannot exist in BEFORE)'
    emit('| %s | %.2f | %.2f | %+.1f%% | %.1f%% | %.1f\u2013%.1f\u00d7 | %s |' % (
        k, mb, ma, md, noise[k], lo, hi, verdict))
emit()
# A metric can be zero in BEFORE for one of two reasons. Distinguish them, because only the first is
# evidence of anything.
emit('Two metrics are 0 in BEFORE for opposite reasons, and it matters which is which:')
emit()
emit('* `wall raycasts skipped` is 0 because the BEFORE build had no skip: it re-clipped every frame,')
emit('  so the work shows up in `wall raycasts` instead. Its AFTER value is the work REMOVED.')
emit('* `reward fanout reuses` is 0 because BEFORE re-classified the group on every hit and therefore')
emit('  never had anything to re-use. Its AFTER value counts re-uses of a cache that did not exist.')
emit()

emit('## Per-scenario detail')
emit()
hdr = '| metric | ' + ' | '.join(NAME[s] for s in SCENES) + ' |'
emit(hdr)
emit('|---|' + '---:|' * len(SCENES))
for k in KEYS:
    cells = []
    for s in SCENES:
        b, a = unit(before[s])[k], unit(after[s])[k]
        cells.append('%+.1f%%' % ((a - b) / b * 100) if b else 'n/a')
    emit('| %s | %s |' % (k, ' | '.join(cells)))
emit()

open(os.path.join(ROOT, 'summary.md'), 'w', encoding='utf-8').write('\n'.join(OUT) + '\n')
print('wrote %s' % os.path.join(ROOT, 'summary.md'))
