"""Paired, song-group bootstrap for producer-label agreement, not audio quality."""
import random
import statistics


def assess(group_deltas, *, split):
    metrics = {}
    rng = random.Random(42)
    for name, groups in sorted(group_deltas.items()):
        means = [statistics.mean(values) for values in groups.values() if values]
        if not means:
            continue
        samples = sorted(statistics.mean(rng.choices(means, k=len(means))) for _ in range(2000))
        metrics[name] = {'source_groups': len(means), 'mean_improvement': statistics.mean(means),
                         'confidence_interval_95': [samples[50], samples[1949]]}
    overall = {k: v for k, v in metrics.items() if k.startswith('all/')}
    enough = set(overall) == {'all/apply_accuracy', 'all/effective_scale_mae'} and all(v['source_groups'] >= 10 for v in overall.values())
    better = any(v['confidence_interval_95'][0] > 0 for v in overall.values())
    no_overall_regression = all(v['confidence_interval_95'][0] >= 0 for v in overall.values())
    no_slice_regression = all(v['mean_improvement'] >= -1e-9 for v in metrics.values())
    passed = split == 'test' and enough and better and no_overall_regression and no_slice_regression
    return {'status': 'passed' if passed else ('insufficient_independent_songs' if not enough else 'not_demonstrated'),
            'meaning': 'Agreement with recorded or inferred producer targets; not proof of better sound.',
            'minimum_source_groups_per_objective': 10,
            'paired_song_bootstrap': metrics,
            'listening_test_required': True, 'publication_approved': False}
