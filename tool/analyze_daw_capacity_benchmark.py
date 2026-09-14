"""Aggregate synthetic PRO17 JSONL logs; no network or project mutation."""
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path


def percentile(values, fraction):
    values = sorted(values)
    position = (len(values) - 1) * fraction
    low, high = math.floor(position), math.ceil(position)
    return values[low] + (values[high] - values[low]) * (position - low)


def summarize(paths):
    groups = defaultdict(lambda: defaultdict(list))
    counts = defaultdict(int)
    observed = set()
    for path in paths:
        for line in Path(path).read_text().splitlines():
            prefix = '[PRO17_PERF] '
            if not line.startswith(prefix):
                continue
            event = json.loads(line[len(prefix):])
            kind = event.get('event')
            if kind in ('slow_frame', 'event_loop_stall'):
                counts[kind] += 1
            if kind not in ('operation_end', 'operation_visible_frame', 'operation_phase'):
                continue
            if event.get('warmup'):
                continue
            if event.get('result', 'success') != 'success':
                raise ValueError('A measured operation failed; do not score incomplete acceptance.')
            key = (event['variant'], event['rows'], event['clips'], event['operation'], event['run'])
            metric = event['phase'] if kind == 'operation_phase' else kind
            identity = (event['session_id'], event['operation_id'], kind,
                        event.get('phase'))
            if identity in observed:
                raise ValueError('Duplicate measurements; do not count repeated logs as independent samples.')
            observed.add(identity)
            value = event['phase_ms'] if kind == 'operation_phase' else event['elapsed_ms']
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise ValueError('Invalid timing')
            groups[key][metric].append(value)
    result = []
    for key, metrics in sorted(groups.items()):
        if len(metrics['operation_end']) != len(metrics['operation_visible_frame']):
            raise ValueError('Incomplete visible-frame measurements.')
        variant, rows, clips, operation, run = key
        result.append(dict(variant=variant, rows=rows, clips=clips, operation=operation,
            run=run, metrics={metric: dict(count=len(values),
                median_ms=percentile(values, .5), p95_ms=percentile(values, .95),
                max_ms=max(values)) for metric, values in sorted(metrics.items())}))
    return dict(groups=result, events=dict(sorted(counts.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', nargs='+')
    args = parser.parse_args()
    print(json.dumps(summarize(args.logs), sort_keys=True, indent=2))


if __name__ == '__main__':
    main()
