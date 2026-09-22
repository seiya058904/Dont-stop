"""Summarize recorded Chromium spans; never label elapsed trace spans as GPU time.

Usage: python tools/b194-trace-costs.py browser-trace.json.gz summary.json
Inclusive totals overlap. Recorded-child residuals are emitted only for threads
whose complete spans nest correctly; omitted trace categories remain unattributed.
"""
import collections
import gzip
import json
import sys
from pathlib import Path


def summarize(events):
    names = {(e['pid'], e['tid']): e['args'].get('name', '')
             for e in events if e.get('name') == 'thread_name'}
    groups = collections.defaultdict(list)
    for event in events:
        if event.get('ph') == 'X' and event.get('dur', 0) > 0:
            groups[event['pid'], event['tid']].append(event)
    result = []
    for thread, spans in groups.items():
        if names.get(thread) not in ('CrRendererMain', 'CrGpuMain', 'VizCompositorThread'):
            continue
        inclusive = collections.Counter()
        residual = collections.Counter()
        maxima = collections.Counter()
        counts = collections.Counter()
        stack = []
        overlaps = 0
        for event in sorted(spans, key=lambda e: (e['ts'], -e['dur'])):
            name, duration = event['name'], event['dur']
            inclusive[name] += duration
            maxima[name] = max(maxima[name], duration)
            counts[name] += 1
            while stack and stack[-1][0] <= event['ts']:
                _, parent, remaining = stack.pop()
                residual[parent] += remaining
            if stack:
                if event['ts'] + duration <= stack[-1][0]:
                    stack[-1][2] -= duration
                else:
                    overlaps += 1
            stack.append([event['ts'] + duration, name, duration])
        while stack:
            _, name, remaining = stack.pop()
            residual[name] += remaining
        result.append({
            'pid': thread[0], 'tid': thread[1], 'thread': names[thread],
            'partial_overlaps': overlaps,
            'inclusive_top20': [{'name': n, 'sum_ms': v / 1000,
                                 'max_ms': maxima[n] / 1000, 'count': counts[n]}
                                for n, v in inclusive.most_common(20)],
            'recorded_child_residual_top20': None if overlaps else
                [{'name': n, 'ms': v / 1000} for n, v in residual.most_common(20)],
            'long_spans_top20': [{'name': e['name'], 'start_us': e['ts'], 'ms': e['dur'] / 1000}
                                 for e in sorted(spans, key=lambda e: e['dur'], reverse=True)[:20]],
        })
    return {'method': 'Complete X spans only. Inclusive times overlap. Residuals subtract recorded nested children, not all real work. No CPU/GPU utilization claim.',
            'threads': result}


if __name__ == '__main__':
    source, destination = map(Path, sys.argv[1:])
    body = source.read_bytes()
    data = json.loads(gzip.decompress(body) if source.suffix == '.gz' else body)
    destination.write_text(json.dumps(summarize(data['traceEvents']), indent=2), encoding='utf-8')
