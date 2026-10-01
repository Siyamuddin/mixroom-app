import { useEffect, useMemo, useSyncExternalStore } from 'react';
import { VoiceRelay } from './relay';
import { VoiceCompanion } from './session';
import { useElevenSpeech } from './useElevenSpeech';
import './studio.css';

type Props = { userId: string; relayUrl: string; accessToken: () => Promise<string>; onSignOut: () => void };

export function VoiceStudio({ userId, relayUrl, accessToken, onSignOut }: Props) {
  const speech = useElevenSpeech();
  const companion = useMemo(() => new VoiceCompanion(new VoiceRelay(relayUrl, accessToken), speech,
    { userId, storage: typeof window === 'undefined' ? undefined : window.sessionStorage }), [relayUrl, accessToken, speech, userId]);
  const value = useSyncExternalStore(companion.subscribe, companion.snapshot, companion.snapshot);
  useEffect(() => {
    companion.activate();
    const timer = window.setInterval(() => { void companion.tick(); }, 1000);
    const hide = () => { if (document.hidden) void companion.stopConversation(); };
    document.addEventListener('visibilitychange', hide); void companion.tick();
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', hide); companion.deactivate(); };
  }, [companion]);
  const state = value.snapshot?.state;
  const connected = companion.connected;
  const capture = !!state?.recordingPhase && state.recordingPhase !== 'idle';
  const busy = !!value.pendingCommandId || capture || value.phase === 'speaking' || value.phase === 'connecting';
  const canAct = connected && !busy;
  const selected = state?.tracks?.find(track => state.selectedTrackIds?.includes(track.id));
  const status = capture ? captureLabel(state?.recordingPhase) : value.phase === 'idle' ? 'Ready when you are' : phaseLabels[value.phase];
  const action = (type: string, args: Record<string, unknown> = {}) => { void companion.action(type, args); };
  const signOut = async () => { await companion.endSession(); if (!companion.value.sessionId) onSignOut(); };

  return <div className="mixroom-studio">
    <a className="mr-skip" href="#voice-control">Skip to voice controls</a>
    <header className="mr-header">
      <a href="/" className="mr-brand" aria-label="MixRoom home"><span aria-hidden="true">Ⅲ</span> MixRoom<span className="mr-brand-caption">VOICE STUDIO</span></a>
      <div className="mr-header-actions"><span className={`mr-connection ${connected ? 'is-connected' : ''}`}><i aria-hidden="true" />{connected ? 'Mac connected' : 'Mac offline'}</span><button onClick={() => void signOut()} className="mr-text-button">Sign out</button></div>
    </header>
    <main className="mr-main">
      <div className="mr-title-row"><div><p className="mr-eyebrow">YOUR SESSION, WITHIN REACH</p><h1>{state?.projectName || 'Make room for the music.'}</h1><p className="mr-subtitle">Keep your hands on your instrument. Talk to your session.</p></div><span className="mr-session-number">01 <span>/ STUDIO</span></span></div>
      {value.error && <div className="mr-alert" role="alert"><strong>Session notice</strong><p>{value.error}</p><button onClick={() => void companion.tick()}>Check connection</button></div>}
      {!value.sessionId ? <section className="mr-pairing" aria-labelledby="pair-title">
        <div className="mr-pair-art" aria-hidden="true"><span>MAC</span><div /><small>↗</small><span>VOICE</span></div>
        <div><p className="mr-eyebrow">FIRST, CONNECT YOUR STUDIO</p><h2 id="pair-title">One Mac. One conversation.</h2><p>Open your project in the MixRoom Mac app, then enter a pairing code to connect this device.</p><button className="mr-primary" onClick={() => void companion.pair()} disabled={value.phase === 'connecting'}>{value.phase === 'connecting' ? 'Creating code…' : 'Pair your Mac'} <span aria-hidden="true">↗</span></button></div>
      </section> : <>
        {!connected && <section className="mr-pair-code" aria-label="Device pairing"><div><p className="mr-eyebrow">ENTER IN MIXROOM → VOICE SESSION → CONNECT</p><strong>{value.pairingCode || 'Reconnect your Mac'}</strong><p>{value.pairingExpiresAt ? `Pairing code expires at ${new Date(value.pairingExpiresAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}.` : 'Waiting for the paired Mac to publish its project.'}</p></div><button className="mr-secondary" onClick={() => void companion.endSession()}>End session</button></section>}
        <div className="mr-workspace">
          <section className="mr-console" id="voice-control" aria-labelledby="voice-title">
            <div className="mr-section-top"><p className="mr-eyebrow">CONVERSATION</p><span>{selected ? selected.name : 'Select a track on your Mac'}</span></div>
            <div className={`mr-voice-orbit ${value.phase === 'listening' ? 'is-listening' : ''} ${capture ? 'is-recording' : ''}`} aria-hidden="true"><div className="mr-mic"><svg viewBox="0 0 48 48"><rect x="18" y="5" width="12" height="25" rx="6"/><path d="M12 23v2a12 12 0 0 0 24 0v-2M24 37v6M18 43h12"/></svg></div><span className="mr-orbit-label">{capture ? `${Math.ceil(state?.captureRemainingSeconds ?? 0)}s` : 'MIXROOM'}</span></div>
            <p className="mr-eyebrow mr-center">{connected ? 'CONNECTED TO YOUR MAC' : 'WAITING FOR YOUR MAC'}</p>
            <h2 id="voice-title" className="mr-status" aria-live="polite">{status}</h2>
            <p className="mr-prompt">{value.partial || (capture ? 'Command listening is paused. Your take is recorded on the Mac.' : '“Lower the backing track by two decibels.”')}</p>
            <button className={`mr-primary mr-conversation ${value.conversation ? 'is-active' : ''}`} disabled={!connected || (!value.conversation && capture)} onClick={() => void (value.conversation ? companion.stopConversation() : companion.startConversation())}>{value.conversation ? 'End conversation' : 'Start conversation'}<span aria-hidden="true">{value.conversation ? '■' : '↗'}</span></button>
            <p className="mr-hint">Use headphones. Allow microphone access when prompted.</p>
            {capture && <button className="mr-stop" onClick={() => void companion.emergencyStop()}>■ Stop recording</button>}
            <div className="mr-transport"><span>{state?.transport?.playing ? '▶ Playing' : '■ Stopped'}</span><span>{state?.transport?.tempo ?? '—'} <small>BPM</small></span><span>{state?.transport?.timeSignature ?? '—'}</span><span>{time(state?.transport?.positionSeconds ?? 0)}</span></div>
          </section>
          <aside className="mr-session-panels">
            <section className="mr-panel" aria-labelledby="compare-title"><div className="mr-section-top"><h2 id="compare-title">Trust your ears.</h2><span className="mr-small-label">A / B</span></div><p>Listen to the latest verified mix change.</p><div className="mr-segments"><button disabled={!canAct || !state?.comparison?.available} aria-pressed={state?.comparison?.side === 'before'} onClick={() => action('comparison.before')}>Before</button><button disabled={!canAct || !state?.comparison?.available} aria-pressed={state?.comparison?.side === 'after'} onClick={() => action('comparison.after')}>After</button></div><div className="mr-button-row"><button className="mr-text-button" disabled={!canAct || !state?.comparison?.available} onClick={() => action('comparison.keep_before')}>Keep before</button><button className="mr-text-button" disabled={!canAct || !state?.comparison?.available} onClick={() => action('comparison.keep_after')}>Keep after</button><button className="mr-text-button" disabled={!canAct} onClick={() => action('history.undo')}>↶ Undo</button></div>{!state?.comparison?.available && <small className="mr-hint">Make a mix change by voice to compare it.</small>}</section>
            <section className="mr-panel" aria-labelledby="capture-title"><div className="mr-section-top"><h2 id="capture-title">Catch the idea.</h2><span className="mr-small-label">TAKES</span></div><p>Choose an audio track on your Mac, then speak or start a take here.</p><div className="mr-take-actions"><button className="mr-secondary" disabled={!canAct} onClick={() => action('recording.start', { duration_seconds: 10, hum: false })}>● Record 10 seconds</button><button className="mr-secondary" disabled={!canAct} onClick={() => action('recording.start', { duration_seconds: 10, hum: true })}>♫ Hum into keys</button></div><small className="mr-hint">“Record four bars.” · “Turn that melody up an octave.”</small></section>
            <section className="mr-panel mr-notes" aria-labelledby="notes-title"><div className="mr-section-top"><h2 id="notes-title">Leave yourself a note.</h2><button className="mr-text-button" disabled={!canAct} onClick={() => action('notes.list')}>Read aloud</button></div>{state?.notes?.length ? <ul>{state.notes.map(note => <li key={note.id}><button className="mr-note-check" aria-label={`Complete note: ${note.text}`} disabled={!canAct || note.completed} onClick={() => action('notes.complete', { note_id: note.id })}>{note.completed ? '✓' : '○'}</button><div><p className={note.completed ? 'mr-completed' : ''}>{note.text}</p><small>{time(note.playheadMs / 1000)}</small></div></li>)}</ul> : <p className="mr-note-empty">“Remember: try a quieter guitar in the second verse.”<span>Your notes are saved with the local project.</span></p>}</section>
          </aside>
        </div>
        <section className="mr-transcript" aria-labelledby="transcript-title"><div className="mr-section-top"><h2 id="transcript-title">The conversation</h2><span className="mr-small-label">NATIVE-CONFIRMED RESULTS</span></div><div role="log" aria-live="polite" aria-relevant="additions">{value.transcript.length ? value.transcript.map(line => <div className="mr-transcript-row" key={line.id}><span>{line.role === 'you' ? 'YOU' : 'MIXROOM'}</span><p>{line.text}</p>{line.outcome && <small>{outcomeLabel(line.outcome)}</small>}</div>) : <p className="mr-empty-transcript">Your words and completed actions will appear here.</p>}</div></section>
      </>}
      <footer className="mr-footer"><p>Made for the moment an idea arrives.<span>Music stays on your Mac. Command speech is processed by ElevenLabs.</span></p>{value.sessionId && <button className="mr-text-button" onClick={() => void companion.endSession()}>Disconnect studio ↗</button>}</footer>
      {(value.latency.recognitionMs !== undefined || value.latency.responseMs !== undefined) && <details className="mr-diagnostics"><summary>Session timing</summary><p>Transcript commit after last partial: {Math.round(value.latency.recognitionMs ?? 0)} ms · Response audio headers: {Math.round(value.latency.responseMs ?? 0)} ms. These browser measurements exclude native planning and execution.</p></details>}
    </main>
  </div>;
}
const phaseLabels = { connecting: 'Opening your microphone…', listening: 'I’m listening.', working: 'Working on your session…', speaking: 'Here’s what happened.', recording: 'Recording your take.', idle: 'Ready when you are' };
function captureLabel(phase?: string) { return ({ awaiting_ready: 'Get ready to record.', countdown: 'Two seconds. Then play.', capturing: 'Your take is rolling.', saving: 'Saving your take…', transcribing: 'Finding the notes…' } as Record<string, string>)[phase ?? ''] ?? 'Recording your take.'; }
function time(seconds: number) { return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`; }
function outcomeLabel(status: string) { return ({ verified: 'Verified', succeeded: 'Complete', clarify: 'Needs your answer', respond: 'Reply', unsupported: 'Not supported', rejected: 'Not applied', failed: 'Could not verify', outcome_unknown: 'Check your project' } as Record<string, string>)[status] ?? status; }
