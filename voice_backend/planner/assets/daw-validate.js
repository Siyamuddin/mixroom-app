// Port of MixRoom ai-v4 contract-6 pure planner logic. No workflow runtime or I/O.
function utf8ByteLength(value) { return new TextEncoder().encode(value).byteLength; }
// Canonical schema helpers. Embedded before plan-validator.js; no modules or I/O.
function mrClone(value) { return JSON.parse(JSON.stringify(value)); }
function mrObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function mrWalk(value, visit, path = '$') {
  visit(value, path);
  if (Array.isArray(value)) value.forEach((v, i) => mrWalk(v, visit, `${path}[${i}]`));
  else if (mrObject(value)) Object.entries(value).forEach(([k, v]) => mrWalk(v, visit, `${path}.${k}`));
}
const mrRuntimeGates = Object.freeze({
  'row.apply_phone_mic_cleanup': 'daw.audio_enhance',
  'clip.separate_stems': 'daw.stem_separate',
  'clip.convert_to_midi': 'daw.midi_compose.audio_to_midi',
});
const mrMidiCommands = new Set(['midi.transpose', 'midi.replace_notes', 'midi.append_notes', 'midi.chop_notes']);
const mrAudioCommands = new Set([
  'clip.trim_to_range', 'clip.glue', 'clip.separate_stems', 'clip.convert_to_midi',
  'clip.set_pitch_semitones', 'clip.adjust_pitch_semitones', 'clip.set_timeline_length_beats',
  'clip.scale_timeline_length', 'clip.set_source_tempo_bpm', 'clip.set_tempo_follow_mode',
  'clip.align_tempo_to_project', 'clip.trim_silence', 'clip.align_first_sound',
  'sample.replace', 'project.set_tempo_from_clip',
]);
const mrMixEffects = Object.freeze({balance:['EQ 3-Band','Compressor','Limiter'],clipper:['Clipper'],compressor:['Compressor'],deesser:['De-Esser'],delay:['Delay'],distortion:['Distortion'],eq:['EQ 3-Band','EQ Parametric'],gain:[],limiter:['Limiter'],pan:[],reverb:['Reverb']});
function mrCommandType(variant) { return variant.properties.type.enum[0]; }
function mrAllowedTypes(request, contracts) {
  const supported = new Set(request.supported_command_types || []);
  const runtime = new Set((request.core_context || {}).runtime_capabilities || []);
  return new Set(contracts.metadata.command_types.filter(type => supported.has(type) && (!mrRuntimeGates[type] || runtime.has(mrRuntimeGates[type]))));
}
function buildPlanTool(request, contracts) {
  const tool = mrClone(request.resource_refs_enabled === true ? contracts.refs : contracts.base);
  const allowed = mrAllowedTypes(request, contracts);
  tool.parameters.properties.commands.maxItems = 32;
  tool.parameters.properties.question_options.maxItems = 4;
  tool.parameters.properties.commands.items.anyOf = tool.parameters.properties.commands.items.anyOf.filter(v => allowed.has(mrCommandType(v)));
  if (!tool.parameters.properties.commands.items.anyOf.length) throw new Error('v3_command_surface_empty');
  for (const variant of tool.parameters.properties.commands.items.anyOf) {
    const type = mrCommandType(variant);
    if (['midi.create_clip','midi.replace_notes','midi.append_notes'].includes(type)) {
      mrWalk(variant, value => { if (mrObject(value) && value.properties && value.properties.notes) value.properties.notes.maxItems = 512; });
    }
  }
  tool.strict = true;
  return tool;
}

// Schema validation + factual ordered-state checks only. Flutter still prepares,
// measures audio, applies commands and verifies/rolls back the transaction.
function mrSchemaErrors(value, schema, path = '$') {
  const fail = code => [{code, path}];
  if (schema.anyOf) {
    let branches = schema.anyOf;
    // Canonical command unions carry a type discriminator; use it for precise errors.
    if (mrObject(value) && typeof value.type === 'string') {
      const selected = branches.filter(b => b.properties && b.properties.type && (b.properties.type.enum || []).includes(value.type));
      if (selected.length) branches = selected;
    }
    const results = branches.map(b => mrSchemaErrors(value, b, path));
    if (results.some(errors => !errors.length)) return [];
    return results.sort((a,b) => a.length - b.length)[0] || fail('v3_schema_any_of');
  }
  const match = type => type === 'null' ? value === null : type === 'object' ? mrObject(value) : type === 'array' ? Array.isArray(value) : type === 'integer' ? Number.isInteger(value) : type === 'number' ? typeof value === 'number' && Number.isFinite(value) : typeof value === type;
  if (schema.type && !(Array.isArray(schema.type) ? schema.type : [schema.type]).some(match)) return fail('v3_schema_type');
  if ('const' in schema && JSON.stringify(value) !== JSON.stringify(schema.const)) return fail('v3_schema_const');
  if (schema.enum && !schema.enum.some(v => JSON.stringify(v) === JSON.stringify(value))) return fail('v3_schema_enum');
  const errors = [];
  if (mrObject(value)) {
    for (const key of schema.required || []) if (!Object.prototype.hasOwnProperty.call(value, key)) errors.push({code:'v3_schema_required', path:`${path}.${key}`});
    for (const [key, child] of Object.entries(value)) {
      if (schema.properties && Object.prototype.hasOwnProperty.call(schema.properties, key)) errors.push(...mrSchemaErrors(child, schema.properties[key], `${path}.${key}`));
      else if (schema.additionalProperties === false) errors.push({code:'v3_schema_extra_field', path:`${path}.${key}`});
    }
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) errors.push(...fail('v3_schema_min_items'));
    if (schema.maxItems !== undefined && value.length > schema.maxItems) errors.push(...fail('v3_schema_max_items'));
    if (schema.items) value.forEach((v,i) => { if (errors.length < 24) errors.push(...mrSchemaErrors(v,schema.items,`${path}[${i}]`)); });
  }
  if (typeof value === 'string') {
    const length = [...value].length;
    if (schema.minLength !== undefined && (length < schema.minLength || (schema.minLength > 0 && !value.trim()))) errors.push(...fail('v3_schema_min_length'));
    if (schema.maxLength !== undefined && length > schema.maxLength) errors.push(...fail('v3_schema_max_length'));
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) errors.push(...fail('v3_schema_nonfinite'));
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(...fail('v3_schema_minimum'));
    if (schema.maximum !== undefined && value > schema.maximum) errors.push(...fail('v3_schema_maximum'));
    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) errors.push(...fail('v3_schema_exclusive_minimum'));
  }
  return errors.slice(0,24);
}
function validatePlan(plan, request, contracts) {
  let tool;
  try { tool = buildPlanTool(request, contracts); }
  catch (_) { return {plan, errors:[{code:'v3_command_surface_empty',path:'$.commands'}]}; }
  const errors = mrSchemaErrors(plan, tool.parameters);
  if (errors.length) return {plan, errors};
  const bad = (code, path) => { throw {code, path}; };
  const requireFact = (test, code, path) => { if (!test) bad(code,path); };
  const context = request.core_context || {};
  const project = context.project || {};
  const capacity = project.row_capacity || {};
  const maxRows = 'creation_limit' in capacity ? capacity.creation_limit : capacity.max_rows;
  const rows = new Map(), clips = new Map(), groups = new Map(), instances = new Map(), outputs = new Map();
  const effects = new Map((context.effects || []).map(e => [e.effect_id, e]));
  const instruments = new Set(context.instruments || []);
  const catalog = new Map((context.instrument_catalog || []).map(i => [i.instrument_id,i]));
  const assets = new Set((context.library_assets || []).map(a => a.asset_id));
  const ids = new Set();
  const cleanupIds = new Set(plan.commands.filter(c => c.type==='row.apply_phone_mic_cleanup').map(c => c.arguments.row_id));
  const stable = id => `id:${id}`;
  const refKey = ref => JSON.stringify([ref.command_id,ref.output]);
  const resource = (resourceKind, data) => ({resourceKind,alive:true,...data});
  for (const row of context.rows || []) {
    const r = resource('row',{key:stable(row.row_id),kind:row.lane_kind,instrument_id:row.instrument_id,mixable:row.mix_processing_supported === true,original:row});
    rows.set(r.key,r);
    for (const effect of row.effects || []) instances.set(effect.effect_instance_id,{...effect,row:r,alive:true});
  }
  for (const clip of context.clips || []) {
    const c = resource('clip',{key:stable(clip.clip_id),row:rows.get(stable(clip.row_id)),kind:clip.kind,instrument_id:clip.instrument_id || rows.get(stable(clip.row_id))?.instrument_id,start:clip.start_beat,length:clip.timeline_length_beats ?? clip.length_beats,originalLength:clip.length_beats,notes:clip.kind === 'midi' ? mrClone(clip.midi_notes || []) : null,original:clip});
    clips.set(c.key,c);
  }
  for (const group of context.groups || []) groups.set(stable(group.group_id),resource('group',{members:group.member_row_ids.map(id => rows.get(stable(id)))}));
  let rowCount = rows.size;
  const liveRows = () => [...rows.values()].filter(r => r.alive);
  const hasMaterial = row => row && row.alive && (row.mixable || [...clips.values()].some(c => c.alive && c.row === row));
  const resolve = (args, kind, path) => {
    const field = `${kind}_id`, refField = `${kind}_ref`;
    let found;
    if (args[refField]) {
      requireFact(request.resource_refs_enabled === true,'v3_resource_refs_disabled',`${path}.${refField}`);
      found = outputs.get(refKey(args[refField]));
      requireFact(found && found.alive && found.resourceKind === kind,'v3_resource_ref_unavailable',`${path}.${refField}`);
    } else {
      found = (kind === 'row' ? rows : kind === 'clip' ? clips : groups).get(stable(args[field]));
      requireFact(found && found.alive,'v3_target_unavailable',`${path}.${field}`);
    }
    return found;
  };
  const publish = (id,port,value) => { outputs.set(JSON.stringify([id,port]),value); };
  const addRow = (key,kind,instrument_id,original={}) => {
    const row = resource('row',{key,kind,instrument_id,mixable:false,original}); rows.set(key,row); rowCount++;
    requireFact(maxRows == null || rowCount <= maxRows,'v3_plan_row_capacity_exceeded','$.commands');
    return row;
  };
  const addClip = (key,data) => { const clip = resource('clip',{key,...data}); clips.set(key,clip); return clip; };
  const detachRows = members => {
    for (const group of groups.values()) if (group.alive) {
      group.members = group.members.filter(row => !members.includes(row));
      if (group.members.length < 2) group.alive = false;
    }
  };
  const removeClip = clip => {
    clip.alive = false;
    if (clip.row && ![...clips.values()].some(c => c.alive && c.row === clip.row)) clip.row.mixable = false;
  };
  const destination = (args,kind,path,id) => {
    if (args.new_row) return addRow(`embedded:${id}`,kind,args.new_row.instrument_id);
    const row = resolve(args,'row',path);
    requireFact(row.kind === kind,'v3_plan_target_type_invalid',path);
    return row;
  };
  const pitches = (notes,instrument_id,path) => {
    const ranges = catalog.get(instrument_id)?.playable_pitch_ranges || [];
    for (let i=0; i<notes.length; i++) requireFact(Number.isInteger(notes[i].pitch) && notes[i].pitch >= 0 && notes[i].pitch <= 127 && (!ranges.length || ranges.some(r => notes[i].pitch >= r.low && notes[i].pitch <= r.high)),'v3_midi_instrument_pitch_unavailable',`${path}[${i}].pitch`);
  };
  const maxEnd = notes => Math.max(0,...(notes || []).map(n => n.start_beat+n.length_beats));
  const originalTempoStable = !plan.commands.some(c => ['project.set_tempo','project.set_tempo_from_clip'].includes(c.type));
  try {
    const serialized=JSON.stringify(plan);
    let planBytes=0; for(const ch of serialized) { const n=ch.codePointAt(0); planBytes+=n<=127?1:n<=2047?2:n<=65535?3:4; }
    requireFact(planBytes<=64000,'v3_provider_plan_too_large','$');
    requireFact(plan.user_message.trim().length > 0,'v3_user_message_invalid','$.user_message');
    requireFact((plan.outcome === 'plan') === (plan.commands.length > 0),'v3_outcome_command_mismatch','$.outcome');
    requireFact(plan.outcome === 'clarify' || plan.question_options.length === 0,'v3_unexpected_question_options','$.question_options');
    requireFact(plan.question_options.every(s => s.trim().length > 0),'v3_question_options_invalid','$.question_options');
    let noteBudget=0;
    for (let i=0; i<plan.commands.length; i++) {
      const command=plan.commands[i], a=command.arguments, type=command.type, id=command.command_id, path=`$.commands[${i}].arguments`;
      requireFact(id.trim().length > 0 && !ids.has(id),'v3_command_id_invalid',`$.commands[${i}].command_id`); ids.add(id);
      // Validate every direct identifier and typed reference against the state at this step.
      mrWalk(a,(value,p) => {
        if (!mrObject(value)) return;
        for (const kind of ['row','clip','group']) {
          if (`${kind}_id` in value || `${kind}_ref` in value) resolve(value,kind,p);
          const plural=value[`${kind}_ids`];
          if (Array.isArray(plural)) plural.forEach(v => resolve({[`${kind}_id`]:v},kind,p));
        }
        if (value.destination_row_id != null) resolve({row_id:value.destination_row_id},'row',p);
        if ('instrument_id' in value) requireFact(instruments.has(value.instrument_id),'v3_instrument_id_unknown',`${p}.instrument_id`);
        if ('asset_id' in value) requireFact(assets.has(value.asset_id),'v3_asset_id_unknown',`${p}.asset_id`);
        if ('effect_instance_id' in value) requireFact(instances.get(value.effect_instance_id)?.alive,'v3_effect_instance_unknown',`${p}.effect_instance_id`);
      },path);
      if (['transport.set_playing','transport.restart'].includes(type)) requireFact(context.transport?.recording!==true,'v3_transport_recording_active',path);
      if (mrMidiCommands.has(type)) requireFact(resolve(a,'clip',path).kind === 'midi','v3_plan_target_type_invalid',path);
      if (mrAudioCommands.has(type)) {
        const targets=type === 'clip.glue' ? a.sources || a.clip_ids.map(clip_id => ({clip_id})) : [a];
        for (const target of targets) requireFact(resolve(target,'clip',path).kind === 'audio','v3_plan_target_type_invalid',path);
      }
      if (['midi.create_clip','midi.replace_notes','midi.append_notes'].includes(type)) {
        noteBudget+=a.notes.length; requireFact(noteBudget <= 512,'v3_generated_midi_limit',`${path}.notes`);
      }
      switch(type) {
        case 'row.create': {
          const row=addRow(`generated:${id}.row`,a.lane.kind === 'midi' ? 'instrument':'audio',a.lane.instrument_id);
          publish(id,'row',row); break;
        }
        case 'row.delete': {
          const row=resolve(a,'row',path); requireFact(rowCount > 1,'v3_row_delete_last_remaining',path);
          detachRows([row]); row.alive=false; rowCount--;
          for (const clip of clips.values()) if (clip.row===row) removeClip(clip);
          for (const effect of instances.values()) if (effect.row===row) effect.alive=false;
          break;
        }
        case 'row.set_instrument': {
          const row=resolve(a,'row',path); requireFact(row.kind === 'instrument','v3_plan_target_type_invalid',path);
          row.instrument_id=a.instrument_id;
          for (const clip of clips.values()) if (clip.alive && clip.row===row && clip.kind==='midi') clip.instrument_id=a.instrument_id;
          break;
        }
        case 'row.apply_phone_mic_cleanup': {
          const row=resolve(a,'row',path);
          requireFact(row.kind === 'audio' && [...clips.values()].some(c => c.alive && c.row===row && c.kind==='audio'),'v3_phone_cleanup_audio_missing',path);
          requireFact(['EQ Parametric','De-Esser','Dynamic Softener','Compressor','Limiter'].every(e => effects.has(e)),'v3_phone_cleanup_unavailable',path);
          break;
        }
        case 'group.create': {
          const members=(a.members || a.row_ids.map(row_id => ({row_id}))).map(t => resolve(t,'row',path));
          requireFact(new Set(members).size===members.length,'v3_group_members_duplicate',path);
          detachRows(members); const group=resource('group',{members}); groups.set(`generated:${id}.group`,group); publish(id,'group',group); break;
        }
        case 'group.remove_row': {
          const group=resolve(a,'group',path), row=resolve(a,'row',path);
          requireFact(group.members.includes(row),'v3_group_membership_mismatch',path);
          group.members=group.members.filter(r => r!==row); if (group.members.length<2) group.alive=false; break;
        }
        case 'midi.create_clip': {
          const row=destination(a.destination,'instrument',`${path}.destination`,id);
          requireFact(a.length_beats>=0.001 && a.length_beats <= 8*(project.beats_per_bar || 4),'v3_midi_arrangement_limit',`${path}.length_beats`);
          requireFact(maxEnd(a.notes)<=a.length_beats,'v3_midi_note_out_of_bounds',`${path}.notes`);
          pitches(a.notes,row.instrument_id,`${path}.notes`);
          publish(id,'midi_clip',addClip(`generated:${id}.midi_clip`,{row,kind:'midi',instrument_id:row.instrument_id,start:a.start_beat,length:a.length_beats,notes:mrClone(a.notes)})); break;
        }
        case 'midi.replace_notes': case 'midi.append_notes': {
          const clip=resolve(a,'clip',path); pitches(a.notes,clip.instrument_id,`${path}.notes`);
          if(type==='midi.replace_notes') {
            const end=maxEnd(a.notes);
            // Match extend_1ms_v1 only for an existing clip with stable tempo.
            if(clip.original && originalTempoStable && project.midi_boundary_policy==='extend_1ms_v1' && project.bpm>0 && end>clip.length) {
              const scale=60000000/project.bpm;
              if(Math.ceil(end*scale)-Math.floor(clip.originalLength*scale+0.5)<=1000) clip.length=Math.ceil(end*scale)/scale;
            }
            requireFact(clip.length==null || end<=clip.length+0.000001,'v3_midi_note_out_of_bounds',`${path}.notes`);
            clip.notes=mrClone(a.notes);
          } else if (clip.notes !== null && clip.length != null) {
            const anchor=Math.max(clip.length,maxEnd(clip.notes));
            clip.notes.push(...a.notes.map(n => ({...n,start_beat:n.start_beat+anchor})));
            clip.length=anchor+maxEnd(a.notes);
            requireFact(clip.notes.length<=512,'v3_midi_result_limit',`${path}.notes`);
          } else { clip.notes=null; clip.length=null; }
          break;
        }
        case 'midi.transpose': {
          const clip=resolve(a,'clip',path);
          if(clip.notes!==null) { const next=clip.notes.map(n => ({...n,pitch:n.pitch+a.semitones})); pitches(next,clip.instrument_id,path); clip.notes=next; }
          break;
        }
        case 'midi.chop_notes': {
          const clip=resolve(a,'clip',path), start=a.range?.start_beat ?? 0, end=a.range?.end_beat ?? clip.length;
          requireFact(end==null || (end>start && (clip.length==null || end<=clip.length+0.000001)),'v3_midi_chop_range_invalid',`${path}.range`);
          // Notes from runtime-generated clips are checked by Flutter after rendering.
          if (clip.notes!==null && end!=null) {
            const step=4/a.subdivision, next=[];
            for(const n of clip.notes) {
              const nEnd=n.start_beat+n.length_beats;
              if(nEnd<=start || n.start_beat>=end) { next.push(n); continue; }
              if(n.start_beat<start) next.push({...n,length_beats:start-n.start_beat});
              const chopStart=Math.max(start,n.start_beat), chopEnd=Math.min(end,nEnd);
              for(let at=chopStart,j=0; at<chopEnd-0.000001; at=chopStart+(++j)*step) {
                next.push({...n,start_beat:at,length_beats:Math.min(step,chopEnd-at),velocity:Math.max(.05,n.velocity-j*a.velocity_decay_per_slice)});
                requireFact(next.length<=512,'v3_midi_result_limit',path);
              }
              if(nEnd>end) next.push({...n,start_beat:end,length_beats:nEnd-end});
            }
            requireFact(next.length<=512,'v3_midi_result_limit',path); clip.notes=next;
          }
          break;
        }
        case 'sample.place': {
          const row=destination(a.destination,'audio',`${path}.destination`,id);
          for(let p=0;p<a.placements.length;p++) {
            const clip=addClip(`generated:${id}.sample:${p}`,{row,kind:'audio',start:a.placements[p].start_beat,length:null,notes:null});
            if(a.placements.length===1) publish(id,'audio_clip',clip);
          }
          break;
        }
        case 'clip.separate_stems': case 'clip.convert_to_midi': {
          const source=resolve(a,'clip',path); requireFact(source.original?.source_available!==false,'v3_clip_source_unavailable',path);
          const parts=type==='clip.convert_to_midi' ? [['midi_row','midi_clip','instrument','midi']] : [['vocals_row','vocals_clip','audio','audio'],['instrumental_row','instrumental_clip','audio','audio']];
          for(const [rowPort,clipPort,rowKind,clipKind] of parts) {
            const row=addRow(`generated:${id}.${rowPort}`,rowKind,a.instrument_id);
            const clip=addClip(`generated:${id}.${clipPort}`,{row,kind:clipKind,instrument_id:a.instrument_id,start:source.start,length:source.length,notes:null});
            publish(id,rowPort,row); publish(id,clipPort,clip);
          }
          break;
        }
        case 'clip.delete': removeClip(resolve(a,'clip',path)); break;
        case 'clip.duplicate_to': {
          const source=resolve(a,'clip',path), row=a.destination_row_id == null ? source.row : resolve({row_id:a.destination_row_id},'row',path);
          requireFact(row.kind === (source.kind==='midi' ? 'instrument':'audio'),'v3_plan_target_type_invalid',path);
          const clip=addClip(`generated:${id}.copy_clip`,{...source,key:`generated:${id}.copy_clip`,alive:true,row,start:a.start_beat,notes:source.notes===null?null:mrClone(source.notes),instrument_id:source.kind==='midi'?row.instrument_id:source.instrument_id,original:undefined});
          if(clip.notes) pitches(clip.notes,clip.instrument_id,path); publish(id,'copy_clip',clip); break;
        }
        case 'clip.split_at': {
          const source=resolve(a,'clip',path), offset=source.start==null ? null : a.at_beat-source.start;
          requireFact(offset==null || (offset>0 && (source.length==null || offset<source.length)),'v3_clip_split_out_of_bounds',path);
          removeClip(source);
          for(const [port,isRight] of [['left_clip',false],['right_clip',true]]) {
            const clip=addClip(`generated:${id}.${port}`,{...source,key:`generated:${id}.${port}`,alive:true,start:isRight?a.at_beat:source.start,length:offset==null||source.length==null?null:(isRight?source.length-offset:offset),notes:null,original:undefined});
            publish(id,port,clip);
          }
          break;
        }
        case 'clip.glue': {
          const sources=(a.sources || a.clip_ids.map(clip_id => ({clip_id}))).map(t => resolve(t,'clip',path));
          requireFact(new Set(sources).size===sources.length && sources.every(c => c.row===sources[0].row),'v3_clip_glue_sources_invalid',path);
          const known=sources.every(c => c.start!=null && c.length!=null), start=known?Math.min(...sources.map(c => c.start)):null;
          const length=known?Math.max(...sources.map(c => c.start+c.length))-start:null;
          sources.forEach(removeClip); publish(id,'glued_clip',addClip(`generated:${id}.glued_clip`,{row:sources[0].row,kind:'audio',start,length,notes:null})); break;
        }
        case 'clip.move_by_beats': {
          const clip=resolve(a,'clip',path); if(clip.start!=null) { clip.start+=a.delta_beats; requireFact(clip.start>=0,'v3_clip_negative_start',path); } break;
        }
        case 'clip.trim_to_range': {
          const clip=resolve(a,'clip',path);
          requireFact(a.end_beat>a.start_beat && (clip.start==null || (a.start_beat>=clip.start-0.000001 && (clip.length==null || a.end_beat<=clip.start+clip.length+0.000001))),'v3_clip_trim_out_of_bounds',path);
          clip.start=a.start_beat; clip.length=a.end_beat-a.start_beat; break;
        }
        case 'clip.set_timeline_length_beats': resolve(a,'clip',path).length=a.length_beats; break;
        case 'clip.scale_timeline_length': { const c=resolve(a,'clip',path); if(c.length!=null)c.length*=a.factor; break; }
        case 'sample.replace': resolve(a,'clip',path).length=null; break;
        case 'effect.ensure_configured': {
          const targetRow=resolve(a,'row',path);
          requireFact(!cleanupIds.has(targetRow.original.row_id),'v3_phone_cleanup_effect_conflict',path);
          const effect=effects.get(a.effect_id); requireFact(effect,'v3_effect_id_unknown',`${path}.effect_id`);
          const seen=new Set(), params=new Map((effect.parameters || []).map(p => [p.parameter_id,p]));
          for(let p=0;p<a.parameters.length;p++) {
            const param=a.parameters[p], cap=params.get(param.parameter_id);
            requireFact(cap && !seen.has(param.parameter_id),'v3_effect_parameter_invalid',`${path}.parameters[${p}]`); seen.add(param.parameter_id);
            requireFact(!cap.range || (param.value>=cap.range[0] && param.value<=cap.range[1]),'v3_effect_parameter_range',`${path}.parameters[${p}].value`);
          }
          break;
        }
        case 'effect.remove': case 'effect.set_bypassed': {
          const effect=instances.get(a.effect_instance_id);
          requireFact(!cleanupIds.has(effect.row.original.row_id),'v3_phone_cleanup_effect_conflict',path);
          if(type==='effect.remove') effect.alive=false; break;
        }
        case 'automation.gain_fade': requireFact(a.end_beat>a.start_beat,'v3_fade_range_invalid',path); break;
        case 'automation.set_points': case 'automation.clear': {
          const row=resolve(a,'row',path), raw=a.automation_target_id, target=raw.replace(/^row:\d+:/,'');
          const allowed=new Set((row.original.automation_targets || []).filter(t => mrObject(t) && t.isOrphan!==true && t.is_orphan!==true && t.uiVisible!==false && t.ui_visible!==false).map(t => t.target_id || t.id).filter(Boolean));
          requireFact(row.original.row_id == null ? ['volume','mix:gain','mix:pan'].includes(target) : allowed.has(target),'v3_automation_target_unknown',`${path}.automation_target_id`);
          if(raw.startsWith('row:')) requireFact(raw.startsWith(`row:${row.original.row_id}:`),'v3_automation_target_wrong_owner',`${path}.automation_target_id`);
          if(a.points) requireFact(a.points.every((p,i) => i===0 || p.beat>a.points[i-1].beat),'v3_automation_points_order',`${path}.points`);
          break;
        }
        case 'mix.apply_goal': {
          for(const intent of a.intents) requireFact((mrMixEffects[intent.kind] || []).every(e => effects.has(e)),'v3_mix_intent_unavailable',`${path}.intents`);
          let targets;
          if(a.target.scope==='row') targets=[resolve(a.target,'row',`${path}.target`)];
          else if(a.target.scope==='group') targets=resolve(a.target,'group',`${path}.target`).members;
          else targets=liveRows();
          requireFact(targets.some(hasMaterial),'v3_mix_audio_missing',`${path}.target`);
          requireFact(a.target.scope==='master' || !targets.some(r => cleanupIds.has(r.original.row_id)),'v3_phone_cleanup_effect_conflict',`${path}.target`);
          if(a.reference) {
            const row=resolve(a.reference,'row',`${path}.reference`);
            requireFact(row.original.has_analyzable_audio===true,'v3_mix_reference_audio_missing',`${path}.reference`);
            requireFact(a.target.scope!=='master','v3_mix_master_reference_unsupported',`${path}.reference`);
            requireFact(a.target.scope!=='row' || !targets.includes(row),'v3_mix_reference_equals_target',`${path}.reference`);
          }
          break;
        }
        case 'project.set_tempo': case 'project.set_tempo_from_clip':
          // Subsequent time-based checks defer to Flutter when tempo remaps the timeline.
          for(const clip of clips.values()) if(clip.kind==='audio') { clip.start=null; clip.length=null; }
          break;
        case 'clip.align_tempo_to_project': case 'clip.set_tempo_follow_mode': case 'clip.set_source_tempo_bpm': case 'clip.trim_silence': case 'clip.align_first_sound': {
          const clip=resolve(a,'clip',path); clip.start=null; clip.length=null; break;
        }
      }
    }
    return {plan,errors:[]};
  } catch(error) {
    return {plan,errors:[mrObject(error) && error.code && error.path ? error : {code:'v3_validation_internal_error',path:'$'}]};
  }
}

function errorResult(code, status = 502, state = {}) {
  return { ...state, stage: 'respond', httpStatus: status, response: { error: { code } }, errorCode: code };
}


function finalizePlan(state) {
  if (state.stage === "respond") return state;
  if (Date.now() >= state.deadline) return errorResult('v3_upstream_timeout', 504, state);
  let checked;
  try { checked = validatePlan(state.draft, state.request, state.contracts); }
  catch (_) { return errorResult('v3_planner_contract_invalid', 502, state); }
  if (checked.errors.length) return { ...errorResult('v3_planner_contract_invalid', 502, state), validationErrors: checked.errors };
  const trace = { contract_version: 'mixroom_v3_server_contract_6', contract_fingerprint: state.config.contractFingerprint, request_id: String(state.executionId) };
  if (typeof state.request.prompt_trace_id === 'string' && state.request.prompt_trace_id.trim()) trace.prompt_trace_id = state.request.prompt_trace_id.trim();
  return { ...state, stage: 'respond', httpStatus: 200, response: { schema_version: 'v3_plan_response_server_v1', plan: checked.plan, trace } };
}



export { finalizePlan };
