"""Offline scope checks on synthetic exports. No model calls or adoption.

Normal backend semantics remain authoritative. These checks only score task
scope, and conservatively leave unsupported scoring cases for review.
Language and actual client preparation are separate gates.
"""
import argparse
import json
from collections import Counter
from pathlib import Path


def target(arguments, kind):
    if kind + '_id' in arguments:
        return arguments[kind + '_id']
    ref = arguments.get(kind + '_ref', {})
    return ref.get('command_id') if isinstance(ref, dict) else None


def scope(record):
    plan = record.get('plan', {})
    if plan.get('outcome') != 'plan':
        return {'scope_ok': False, 'unnecessary_clarification': plan.get('outcome') == 'clarify'}
    old = {row['row_id'] for row in record['context']['rows']}
    protected = {105} if record['case'] == 'partial_rebuild' else set()
    required_deleted = old - protected
    active = set(old)
    created = set()
    clips = {}
    protected_ok = True
    review = False
    last_row_violation = False
    for command in plan['commands']:
        kind, args = command['type'], command['arguments']
        row = target(args, 'row')
        # The protected row and its old clip must not be touched, including
        # nested destinations, arrays of targets or existing-resource refs.
        def touches(value):
            if isinstance(value, dict):
                if value.get('row_id') in protected or value.get('clip_id') == 'old5':
                    return True
                return any(touches(item) for item in value.values())
            if isinstance(value, list):
                return any(touches(item) for item in value)
            return False
        # Position anchors are read-only references, not edits to that row.
        edit_args = {key: value for key, value in args.items()
                     if not (kind == 'row.create' and key == 'position')}
        if protected and touches(edit_args):
            protected_ok = False
        if kind == 'row.delete':
            last_row_violation |= len(active) <= 1
            active.discard(row)
        elif kind == 'row.create':
            active.add(command['command_id'])
            created.add(command['command_id'])
        elif kind == 'midi.create_clip':
            destination = args['destination']
            destination_row = target(destination, 'row')
            if destination.get('mode') == 'new_row':
                review = True
            clips[command['command_id']] = (destination_row, args)
        elif kind == 'clip.delete':
            clips.pop(target(args, 'clip'), None)
        elif kind in {'row.rename', 'row.set_instrument', 'row.set_volume', 'row.set_pan',
                      'row.set_mute', 'row.set_solo', 'effect.add', 'effect.remove',
                      'effect.set_parameter'}:
            if row is None:
                review = True
        else:
            # Do not falsely certify protected content or final musical scope
            # for operations this small scorer does not model.
            review = True
    new_active = created & active
    musical_rows = {row for row, args in clips.values() if args.get('notes')}
    scope_ok = (not (required_deleted & active) and bool(new_active)
                and new_active <= musical_rows and protected <= active)
    if record['case'] == 'partial_rebuild':
        scope_ok &= len(new_active) == len(required_deleted)
    if record['case'] == 'single_row':
        scope_ok &= len(new_active) == 1 and any(
            row in new_active and args.get('length_beats') == 32
            for row, args in clips.values())
    return {'scope_ok': scope_ok, 'protected_content_ok': protected_ok,
            'last_row_violation': last_row_violation, 'scope_review_required': review,
            'unnecessary_clarification': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    args = parser.parse_args()
    records = [json.loads(line) for line in args.input.read_text().splitlines() if line.strip()]
    for record in records:
        result = scope(record)
        print(json.dumps({'case': record['case'], 'repeat': record['repeat'],
            'variant': record['variant'], 'backend_valid': record.get('backend_valid', False),
            'error': record.get('error'), **result,
            'reply': record.get('plan', {}).get('user_message')}))
    print(json.dumps({'completed': len(records), 'backend_valid_by_variant': dict(Counter(
        r['variant'] for r in records if r.get('backend_valid') and r.get('outcome') == 'plan'))}))


if __name__ == '__main__':
    main()
