#!/usr/bin/env python3
"""Compare human-amount ONNX against the existing refiner on independent songs.

A fixed 10%-range proposal conditions on the demonstrated control/direction, not
its final magnitude. This benchmark measures conditional parameter agreement,
not chat planning or audible quality. Real captured AI traces have a separate
end-to-end evaluator in evaluate_producer_models.py.
"""
from collections import defaultdict
import argparse
import json
import os
from pathlib import Path
import statistics
import time
from train_human_magnitude import train
from human_magnitude_data import extract
from common.mix_magnitude_contract import control_action, starting_value
from common.mix_plugin_contract import proposed_value, parameter_target
from common.mix_resolve import MixResolveService, OnnxMixModelRunner
from evaluate_producer_models import CandidateRunner
from improvement_assessment import assess


def probe(row):
    d=row['descriptor']; action=control_action(d,row['scope'])
    start=row['initial_value']; width=d['max']-d['min']; actions=[]
    if start is None:
        actions.append(control_action({'kind':'insert','effect_name':d['effect_name']},row['scope']))
        proposed=d['min']+.5*width
    else: proposed=max(d['min'],min(d['max'],start+row['direction']*.1*width))
    action['data'].update(mode='set',value=proposed); action['data'].pop('delta',None)
    actions.append(action)
    return actions


def value_of(action,row):
    if action is None: return row['initial_value']
    d=row['descriptor'];data=action['data']
    if d['kind']=='parameter':
        match=parameter_target(row['state_before'],action)
        if match: return proposed_value(match[1],data)
    if data.get('mode')=='set':
        if 'value' in data: return data['value']
        if 'value_norm' in data: return d['min']+data['value_norm']*(d['max']-d['min'])
    start=row['initial_value']
    return start+data.get('delta',0) if start is not None else None


def evaluate(rows,candidate,baseline, *, split='test'):
    candidate.feature_contract();baseline.feature_contract()
    selected=rows if split=='external' else [r for r in rows if r['split']==split]
    if not selected: raise ValueError('No held-out rows')
    trained=set(getattr(candidate,'training_groups',[]))
    baseline_groups=set(getattr(baseline,'training_groups',[]))
    if any(r['group'] in trained or r['group'] in baseline_groups for r in selected): raise ValueError('Evaluation song was used to train a compared model')
    services={'candidate':MixResolveService(candidate),'baseline':MixResolveService(baseline)}
    deltas=defaultdict(lambda:defaultdict(list)); results=[]; used=0; timings=defaultdict(list)
    for row in selected:
        actions=probe(row);errors={};decisions={}
        for name,service in services.items():
            start=time.perf_counter();response=service.resolve(project=row['state_before'],goal={},actions=actions,strict=True)
            timings[name].append((time.perf_counter()-start)*1000)
            if response['fallback_used']: raise ValueError('Resolver fallback during comparison')
            entry=response['debug_entries'][-1]; decisions[name]=entry['decision']
            value=value_of(entry.get('after'),row)
            if value is None: raise ValueError('Unable to measure resolved parameter value')
            errors[name]=abs(value-row['native_target'])/(row['descriptor']['max']-row['descriptor']['min'])
        used+=decisions['candidate']=='human_magnitude'
        delta=errors['baseline']-errors['candidate']
        for category in ['all',row['descriptor']['kind'],'source:'+row['source'], 'control:'+row['descriptor'].get('effect_name', row['descriptor']['kind'])+':'+row['descriptor'].get('parameter_name','')]: deltas[category+'/normalized_target_mae'][row['group']].append(delta)
        results.append({'id':row['id'],'group':row['group'],'kind':row['descriptor']['kind'],'errors':errors,'decisions':decisions})
    paired=assess(deltas,split='test')['paired_song_bootstrap']; overall=paired['all/normalized_target_mae']
    enough=overall['source_groups']>=10
    improves=enough and overall['confidence_interval_95'][0]>0 and all(v['mean_improvement']>=0 for v in paired.values())
    return {'benchmark':'fixed_proposal_with_demonstrated_control_and_direction','examples':len(results),
        'songs':len({r['group'] for r in selected}),'candidate_refined':used,'candidate_coverage':used/len(results),
        'mean_error':{name:statistics.mean(r['errors'][name] for r in results) for name in services},
        'models':{name:s._runner.observability_context() for name,s in services.items()},
        'warm_median_ms':{name:statistics.median(t[1:] or t) for name,t in timings.items()},
        'paired_song_statistics':paired,'parameter_agreement_improved':improves,
        'baseline_training_overlap_unknown':True,
        'quality_improvement_proven':False,'listening_test_required':True,'publication_approved':False,
        'per_example':results}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('examples',type=Path)
    p.add_argument('--candidate-directory',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--allow-development-model',action='store_true')
    args=p.parse_args()
    if args.allow_development_model: os.environ['MIX_ALLOW_DEVELOPMENT_MODELS']='true'
    rows=[json.loads(l) for l in args.examples.read_text().splitlines() if l.strip()]
    result=evaluate(rows,CandidateRunner(args.candidate_directory),OnnxMixModelRunner())
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='per_example'},indent=2))

if __name__=='__main__': main()
