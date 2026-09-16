#!/usr/bin/env python3
"""Evaluate contextual action selection on held-out observed choices, including rejections."""
import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import statistics
from human_selection_data import extract_selection
from common.mix_magnitude_contract import control_action, starting_value
from common.mix_selection_contract import features
from common.mix_resolve import MixResolveService, OnnxMixModelRunner
from evaluate_producer_models import CandidateRunner
from improvement_assessment import assess


def probe(row):
    d=row['descriptor'];action=control_action(d,row['scope']);actions=[]
    if d['kind']=='parameter' and d.get('inserted'):
        actions.append(control_action({'kind':'insert','effect_name':d['effect_name']},row['scope']))
    if d['type']=='float':
        start=starting_value(row['state_before'],d,row['scope']);width=d['max']-d['min']
        value=d['min']+.5*width if start is None else max(d['min'],min(d['max'],start+row['direction']*.1*width))
        action['data'].update(mode='set',value=value);action['data'].pop('delta',None)
    elif d['kind']=='parameter':
        action['data'].update(mode='set',value_norm=row['choice']);action['data'].pop('delta',None)
    actions.append(action);return actions


def evaluate(rows,candidate,baseline, *, split='test'):
    candidate.feature_contract();baseline.feature_contract()
    selected=rows if split=='external' else [r for r in rows if r['split']==split]
    if not selected: raise ValueError('No held-out selection rows')
    trained=set(getattr(candidate,'training_groups',set()))|set(getattr(baseline,'training_groups',set()))
    if any(r['group'] in trained for r in selected):raise ValueError('Selection evaluation song was used to train a compared model')
    services={'candidate':MixResolveService(candidate),'baseline':MixResolveService(baseline)}
    results=[];deltas=defaultdict(lambda:defaultdict(list))
    for row in selected:
        decisions={}; supported=False
        for name,service in services.items():
            response=service.resolve(project=row['state_before'],goal=row['goal'],actions=probe(row),strict=True)
            if response['fallback_used']:raise ValueError('Selection replay fell back')
            entry=response['debug_entries'][-1]
            decisions[name]=int(not entry['dropped'])
            if name=='candidate':supported=entry.get('selection_supported',False)
        correct={k:float(v==row['label']) for k,v in decisions.items()}
        for category in ('all','label:'+str(row['label']),row['descriptor']['kind'],'source:'+row['source'],*['diagnosis:'+d for d in row.get('diagnoses',[])],*['strategy:'+s for s in row.get('strategies',[])]):
            deltas[category+'/accuracy'][row['group']].append(correct['candidate']-correct['baseline'])
        results.append({'id':row['id'],'group':row['group'],'label':row['label'],'decisions':decisions,'selection_supported':supported})
    metrics={}
    for name in services:
        recalls={str(label):statistics.mean(r['decisions'][name]==label for r in results if r['label']==label) for label in (0,1) if any(r['label']==label for r in results)}
        metrics[name]={'accuracy':statistics.mean(r['decisions'][name]==r['label'] for r in results),'recall_by_label':recalls,
                       'balanced_accuracy':statistics.mean(recalls.values()) if len(recalls)==2 else None}
    paired=assess(deltas,split='test')['paired_song_bootstrap']
    enough=all(paired.get('label:'+str(label)+'/accuracy',{}).get('source_groups',0)>=10 for label in (0,1))
    better=enough and paired['all/accuracy']['confidence_interval_95'][0]>0 and all(v['mean_improvement']>=0 for v in paired.values())
    return {'examples':len(results),'songs':len({r['group'] for r in results}),'metrics':metrics,
        'selection_supported':sum(r['selection_supported'] for r in results),'paired_song_statistics':paired,
        'selection_agreement_improved':better,'quality_improvement_proven':False,'publication_approved':False,
        'benchmark':'observed_control_and_direction_with_fixed_amount','per_example':results,
        'models':{name:s._runner.observability_context() for name,s in services.items()}}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('examples',type=Path)
    p.add_argument('--candidate-directory',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--allow-development-model',action='store_true');args=p.parse_args()
    if args.allow_development_model:os.environ['MIX_ALLOW_DEVELOPMENT_MODELS']='true'
    rows=[json.loads(l) for l in args.examples.read_text().splitlines() if l.strip()]
    report=evaluate(rows,CandidateRunner(args.candidate_directory),OnnxMixModelRunner())
    args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='per_example'},indent=2))

if __name__=='__main__':main()
