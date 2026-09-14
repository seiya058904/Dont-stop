"""Flag either a material absolute regression or a relative regression above noise."""
def regression_details(baseline, candidate):
    reasons=[]
    for key in ['p95','p99']:
        delta=candidate[key]-baseline[key]
        relative=delta/baseline[key] if baseline[key]>0 else float('inf')
        if delta>8 or (delta>2 and relative>0.20):
            reasons.append(dict(metric=key,absolute_ms=delta,relative=relative))
    return reasons
