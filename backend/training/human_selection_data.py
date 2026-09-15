"""Observed action-choice labels for the first ONNX model.

Never label untouched controls or unplayed alternatives as rejected. Questionnaire
categories condition the reported task; they are not inferred from final values.
"""
import copy
from collections import Counter
from human_magnitude_data import extract, historical_bundles
from common.mix_magnitude_contract import fingerprint, control_action, starting_value, parameter_descriptor, encode_target
from common.mix_selection_contract import features, runtime_target, structural_descriptor, choice_coordinate
from common.mix_plugin_contract import bus_target, parameter_target, effect_target, chain, PARAM_ACTIONS, STRUCTURAL_ACTIONS
from common.plugin_identity import model_plugin_id
from producer_capture_converter import _candidate_actions, _same_target, _sha256, _split

INTENTS = {'level_balance':'balance', 'tone':'eq', 'masking':'eq', 'dynamics':'compressor', 'space_depth':'reverb', 'stereo_image':'pan'}


def episode_goal(episode):
    kinds = list(dict.fromkeys(INTENTS[x] for x in episode.get('diagnoses', []) if x in INTENTS))
    return {'intents':[{'kind':kind} for kind in kinds]} if kinds else {}


def controls_in(project, *, inserted=False):
    from human_magnitude_data import scopes
    descriptors = [{'kind':kind,'type':'float','min':0.0,'max':3.0 if kind=='gain' else 1.0} for kind in ('gain','pan')]
    descriptors.append(structural_descriptor('reset'))
    for scope, state in scopes(project):
        for effect in state.get('effects', []):
            if not effect.get('effectId') or not effect.get('name'): continue
            descriptors.extend(structural_descriptor(k,effect) for k in ('insert','remove'))
            descriptors.extend(parameter_descriptor(effect,p,inserted=inserted) for p in effect.get('parameters',[]) if p.get('id') and p.get('name'))
    return {fingerprint(d):d for d in descriptors}


def final_supported(before, after, action, target):
    """Label only uniquely matchable, actually attempted actions."""
    d, scope, direction, choice = target
    if scope['scope']=='row':
        old = [r for r in before.get('rows',[]) if r.get('row')==scope['row']]
        new = [r for r in after.get('rows',[]) if r.get('row')==scope['row']]
        if len(old)!=1 or len(new)!=1 or not old[0].get('row_id') or old[0]['row_id']!=new[0].get('row_id'): return None
    if d['kind'] in ('gain','pan'):
        start=starting_value(before,d,scope);end=starting_value(after,d,scope)
        if encode_target(d,start) is None or encode_target(d,end) is None: return None
        return int((end-start)*direction>1e-8)
    if d['kind']=='parameter':
        initial=parameter_target(before,action);final=parameter_target(after,action)
        if final is None or final[0].get('isBypassed'): return None
        if initial is not None:
            if not initial[0].get('instanceId') or initial[0]['instanceId']!=final[0].get('instanceId'): return None
            if parameter_descriptor(initial[0],initial[1])!=parameter_descriptor(final[0],final[1]): return None
        elif not d.get('inserted'): return None
        if d['type']=='float':
            if initial is None: return None  # Inserted continuous values train magnitude, not fictitious direction labels.
            start=initial[1].get('value');end=final[1].get('value')
            if encode_target(d,start) is None or encode_target(d,end) is None:return None
            return int((end-start)*direction>1e-8)
        final_choice=choice_coordinate(d,final[1].get('value'))
        return int(final_choice==choice) if final_choice is not None else None
    initial_chain=chain(before,action);final_chain=chain(after,action)
    if initial_chain is None or final_chain is None:return None
    if d['kind']=='insert':
        match=effect_target(after,action)
        if match is None:
            token=action['data'].get('effect_name_contains','').lower()
            return 0 if not any(token in e.get('name','').lower() for e in final_chain) else None
        return int(not match.get('isBypassed',False) and model_plugin_id(match)==d['effect_id'])
    if d['kind']=='remove':
        initial=effect_target(before,action)
        if initial is None or not initial.get('instanceId'):return None
        return int(not any(e.get('instanceId')==initial['instanceId'] for e in final_chain))
    if not initial_chain or any(not e.get('instanceId') for e in initial_chain+final_chain):return None
    return int(not ({e['instanceId'] for e in initial_chain}&{e['instanceId'] for e in final_chain}))


def extract_selection(bundle, *, historical=False):
    if historical:
        adapted, exclusions=historical_bundles(bundle); rows=[]
        for b in adapted:
            selected, reasons=extract_selection(b);exclusions.update(reasons)
            for row in selected:
                row['source']='historical_choice';row['weight']=.5
                row['label_provenance']='submitted_final_snapshot_without_outcome_rating'
            rows.extend(selected)
        return rows, exclusions
    positives, exclusions=extract(bundle,include_discrete=True)
    results={}; group=bundle.get('source_group_ref') or (bundle.get('project_ref') if bundle.get('segmentation_version')=='natural_action_burst_v2' else None)
    if not group:return [],exclusions
    if bundle.get('schema_version')!='producer_training_capture_v4' or not bundle.get('consent_version') or not bundle.get('ended_at'):return [],exclusions
    group=_sha256(group)
    episodes={e.get('episode_id'):e for e in bundle.get('episodes',[])}
    def add(episode, project, d, scope, direction, choice, goal, label, provenance):
        identity=[bundle['session_id'],episode.get('episode_id'),d,scope,direction,choice,goal]
        key=fingerprint(identity)
        row={'id':key,'group':group,'split':_split(group),'session_id':bundle['session_id'],'episode_id':episode.get('episode_id'),
             'descriptor':d,'scope':scope,'direction':direction,'choice':choice,'goal':goal,'label':label,
             'state_before':project,'features':features(project,d,scope,direction,choice,goal),'weight':1.0,
             'source':'observed_choice','label_provenance':provenance,'diagnoses':episode.get('diagnoses',[]), 'strategies':episode.get('strategies',[])}
        if key in results and results[key] is None: return
        if key in results and results[key]['label']!=label:
            results[key]=None;exclusions['conflicting_choice_evidence']+=1
        elif key not in results:results[key]=row
    for row in positives:
        e=episodes[row['episode_id']];d=row['descriptor'];choice=choice_coordinate(d,row['native_target'])
        if choice is not None:
            # Normalize scope to runtime shape, excluding training-only UUIDs.
            scope={k:v for k,v in row['scope'].items() if k in ('scope','row','force_individual_row')}
            add(e,row['state_before'],d,scope,row['direction'],choice,episode_goal(e),1,'retained_human_choice')
    for episode in episodes.values():
        if episode.get('status')!='complete' or episode.get('capture_warning') or (episode.get('outcome_signals') or {}).get('undo_redo_observed'):continue
        if episode.get('producer_outcome') not in ('accepted','partial','rejected') or episode.get('provenance',{}).get('label')!='producer':continue
        initial=episode.get('state_before',{}).get('project_state',{});after=episode.get('state_after',{}).get('project_state',{})
        observed=[]
        if episode.get('historical_actions'):
            observed.append((initial,episode['historical_actions'],episode.get('historical_goal',{}),'auditioned_historical_proposal'))
        for trace in episode.get('inference_traces',[]):
            if not trace.get('fallback_used'):
                observed.append((trace['project_state'],trace.get('resolved_actions',[]),trace.get('goal',{}),'auditioned_ai_proposal'))
        manual=[a for a,source in _candidate_actions(episode,initial) if source=='manual']
        # Parameter indices from manual callbacks are only stable if the chain
        # retained its instance order; otherwise only settled positives survive.
        manual=[a for a in manual if bus_target(initial,a) is None and (a['type'] not in PARAM_ACTIONS or [e.get('instanceId') for e in chain(initial,a) or []]==[e.get('instanceId') for e in chain(after,a) or []])]
        for action in manual:
            action['data']['force_individual_row']=True
            if action['type'] in PARAM_ACTIONS:
                effect=effect_target(initial,action)
                matches=[p for p in (effect or {}).get('parameters',[]) if p.get('id')==action['data'].get('param_name')]
                if len(matches)==1:action['data']['param_name']=matches[0]['name']
        if manual:observed.append((initial,manual,episode_goal(episode),'auditioned_manual_change'))
        for project,actions,goal,provenance in observed:
            controls={**controls_in(project),**controls_in(after,inserted=True)}
            for index,action in enumerate(actions):
                if provenance != 'auditioned_manual_change' and sum(_same_target(action,a) for _,batch,_,source in observed if source != 'auditioned_manual_change' for a in batch) != 1:
                    exclusions['repeated_observed_choice_target']+=1;continue
                target=runtime_target(project,action,actions,index,controls)
                if target is None:exclusions['unresolved_observed_choice']+=1;continue
                label=final_supported(project,after,action,target)
                if episode['producer_outcome']=='rejected': label=0 if label is not None else None
                if label is None:exclusions['ambiguous_observed_choice']+=1;continue
                if provenance == 'auditioned_manual_change' and label == 1: continue
                d,scope,direction,choice=target
                add(episode,project,d,scope,direction,choice,goal,label,provenance)
    return [r for r in results.values() if r is not None],exclusions
