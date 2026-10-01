import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers/promises';
import { VoiceCompanion, type SpeechPort } from '../src/voice/session.ts';
import { VoiceRelay, type SessionSnapshot, type CommandStatus, RelayError } from '../src/voice/relay.ts';

function setup() {
  const state: SessionSnapshot = { sessionId: 'session', status: 'active', projectSessionId: 'project', projectRevision: 3, nativeConnected: true,
    updatedAt: new Date().toISOString(), state: { projectReady: true, recordingPhase: 'idle' } };
  const calls: string[] = []; let status: CommandStatus = { commandId: '', status: 'running' };
  let submitFailure: Error | undefined; let finishSpeech = () => {}; let outputOpen = false;
  let committed: (text: string) => void = () => {};
  const speech: SpeechPort = {
    async listen(_token, _partial, final) { calls.push('listen'); committed = final; },
    async stopListening() { calls.push('stop-input'); },
    async speak() { calls.push('speak'); outputOpen = true; await new Promise<void>(resolve => { finishSpeech = resolve; }); outputOpen = false; },
    stopSpeaking() { calls.push('stop-output'); finishSpeech(); },
  };
  const relay = {
    baseUrl: 'https://relay.test/api/voice',
    async createPairing() { return { sessionId: 'session', pairingCode: '2345-6789-ABCD', expiresAt: new Date(Date.now() + 300000).toISOString() }; },
    async presence() { calls.push('presence'); }, async state() { return structuredClone(state); },
    async submit(command: { commandId: string }) { calls.push('submit'); status.commandId = command.commandId; if (submitFailure) throw submitFailure; return status; },
    async status() { calls.push('status'); return status; }, async token() { return { token: 'temporary' }; },
    async tts() { calls.push('tts'); return new Response('audio'); }, async ready() { assert.equal(outputOpen, false); calls.push('ready'); },
    async emergencyStop() { calls.push('emergency'); }, async revoke() { calls.push('revoke'); },
  } as unknown as VoiceRelay;
  const client = new VoiceCompanion(relay, speech, { userId: 'owner' });
  return { client, relay, speech, state, calls, committed: (text: string) => committed(text), finishSpeech: () => finishSpeech(), setFailure: (error: Error) => { submitFailure = error; },
    complete: (nativeStatus = 'verified') => { status = { commandId: status.commandId, status: 'succeeded', result: { commandId: status.commandId, status: 'succeeded', message: 'Verified by Mac', details: { nativeStatus } } }; } };
}

test('duplicate committed transcripts submit one command and only native results are spoken', async () => {
  const f = setup(); await f.client.pair(); await f.client.startConversation();
  f.committed('Lower backing by two decibels'); f.committed('Lower backing by two decibels'); await setImmediate();
  assert.equal(f.calls.filter(x => x === 'submit').length, 1); assert.equal(f.calls.includes('tts'), false);
  f.complete(); await f.client.tick(); await setImmediate();
  assert.equal(f.calls.filter(x => x === 'tts').length, 1);
  assert.equal(f.client.value.transcript.at(-1)?.outcome, 'verified');
  await f.client.tick(); assert.equal(f.calls.filter(x => x === 'tts').length, 1);
  f.client.dispose();
});
test('a lost submission response queries its command without submitting another edit', async () => {
  const f = setup(); await f.client.pair(); f.setFailure(new TypeError('network lost'));
  await f.client.submit('utterance', { text: 'quieter by 2 dB' }); const id = f.client.value.pendingCommandId;
  await f.client.tick(); await f.client.tick();
  assert.equal(f.calls.filter(x => x === 'submit').length, 1); assert.equal(f.client.value.pendingCommandId, id);
  f.complete(); await f.client.tick(); assert.equal(f.client.value.pendingCommandId, null); f.client.dispose();
});
test('capture readiness waits for completed speech and released input; polling stays alive', async () => {
  const f = setup(); await f.client.pair(); await f.client.startConversation();
  f.state.state.recordingPhase = 'awaiting_ready'; f.state.state.captureId = 'capture';
  await f.client.tick(); await setImmediate(); assert.equal(f.calls.includes('ready'), false);
  const heartbeats = f.calls.filter(x => x === 'presence').length;
  await f.client.tick(); assert.ok(f.calls.filter(x => x === 'presence').length > heartbeats);
  f.finishSpeech(); await setImmediate(); assert.equal(f.calls.filter(x => x === 'ready').length, 1);
  assert.equal(f.calls.lastIndexOf('stop-input') < f.calls.indexOf('ready'), true);
  f.state.state.recordingPhase = 'capturing'; await f.client.tick();
  assert.equal(f.client.value.phase, 'recording'); f.client.dispose();
});
test('emergency stop bypasses pending command and cancels readiness', async () => {
  const f = setup(); await f.client.pair(); await f.client.submit('session_action', { type: 'recording.start', arguments: { duration_seconds: 60 } });
  f.state.state.recordingPhase = 'awaiting_ready'; f.state.state.captureId = 'capture';
  await f.client.tick(); await setImmediate(); await f.client.emergencyStop(); await setImmediate();
  assert.ok(f.calls.includes('emergency')); assert.equal(f.calls.includes('ready'), false);
  assert.equal(f.calls.filter(x => x === 'submit').length, 1); f.client.dispose();
});
test('clarification is rendered distinctly from verified edits', async () => {
  const f = setup(); await f.client.pair(); await f.client.submit('utterance', { text: 'turn down vocal' }); f.complete('clarify'); await f.client.tick();
  assert.equal(f.client.value.transcript.at(-1)?.outcome, 'clarify'); f.client.dispose();
});
test('stale project rejection unlocks input without reporting success', async () => {
  const f = setup(); await f.client.pair(); f.setFailure(new RelayError('Project changed', 409, 'stale_project'));
  await f.client.submit('utterance', { text: 'mute vocal' });
  assert.equal(f.client.value.pendingCommandId, null); assert.equal(f.client.value.error, 'Project changed');
  assert.equal(f.calls.includes('tts'), false); f.client.dispose();
});
test('native disconnection stops command listening', async () => {
  const f = setup(); await f.client.pair(); await f.client.startConversation();
  const listens = f.calls.filter(x => x === 'listen').length;
  f.state.nativeConnected = false; await f.client.tick(); f.committed('mute vocal'); await setImmediate();
  assert.equal(f.calls.includes('submit'), false); assert.equal(f.calls.filter(x => x === 'listen').length, listens); f.client.dispose();
  assert.equal(f.client.value.phase, 'idle');
});

function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function memoryStorage() {
  const values = new Map<string, string>();
  return { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value); }, removeItem: (key: string) => { values.delete(key); } };
}

test('StrictMode cleanup and activation restart the same companion and ignore prior callbacks', async () => {
  const f = setup(); const callbacks: ((text: string) => void)[] = [];
  f.speech.listen = async (_token, _partial, final) => { callbacks.push(final); };
  await f.client.pair(); await f.client.startConversation();
  f.client.deactivate(); f.client.activate(); await f.client.tick(); await f.client.startConversation();
  assert.equal(callbacks.length, 2); assert.equal(f.client.value.phase, 'listening');
  callbacks[0]('old session words'); await setImmediate(); assert.equal(f.calls.includes('submit'), false);
  callbacks[1]('current words'); await setImmediate(); assert.equal(f.calls.filter(x => x === 'submit').length, 1);
  f.client.dispose();
});

test('stop and restart cannot activate a stale token', async () => {
  const f = setup(); await f.client.pair();
  const first = deferred<{ token: string }>(), second = deferred<{ token: string }>(); let tokenCalls = 0;
  f.relay.token = () => ++tokenCalls === 1 ? first.promise : second.promise;
  const started = f.client.startConversation(); await f.client.stopConversation(); const restarted = f.client.startConversation();
  second.resolve({ token: 'new' }); await restarted;
  first.resolve({ token: 'old' }); await started;
  assert.equal(f.calls.filter(x => x === 'listen').length, 1); assert.equal(f.client.value.phase, 'listening');
  f.client.dispose();
});

test('old listener errors cannot end a restarted conversation', async () => {
  const f = setup(); await f.client.pair(); const errors: ((message: string) => void)[] = [];
  f.speech.listen = async (_token, _partial, _final, error) => { errors.push(error); };
  await f.client.startConversation(); await f.client.stopConversation(); await f.client.startConversation();
  errors[0]('Old connection closed');
  assert.equal(f.client.value.phase, 'listening'); assert.equal(f.client.value.conversation, true); assert.equal(f.client.value.error, null);
  f.client.dispose();
});

test('an error while the speech adapter opens cannot later publish listening state', async () => {
  const f = setup(); await f.client.pair();
  f.speech.listen = async (_token, _partial, _final, error) => { error('Microphone disconnected'); };
  await f.client.startConversation();
  assert.equal(f.client.value.phase, 'idle'); assert.equal(f.client.value.conversation, false); assert.equal(f.client.value.error, 'Microphone disconnected');
  f.client.dispose();
});

test('late rejection from an ended session cannot clear a new session command', async () => {
  const f = setup(); await f.client.pair(); const old = deferred<CommandStatus>();
  f.relay.submit = () => old.promise;
  const previous = f.client.submit('utterance', { text: 'old change' }); await setImmediate();
  await f.client.endSession();
  f.state.sessionId = 'second-session'; f.relay.createPairing = async () => ({ sessionId: 'second-session', pairingCode: 'second', expiresAt: new Date().toISOString() });
  await f.client.pair(); f.relay.submit = async command => ({ commandId: command.commandId, status: 'running' });
  await f.client.submit('utterance', { text: 'new change' }); const currentId = f.client.value.pendingCommandId;
  old.reject(new RelayError('Old session revoked', 410, 'revoked')); await previous;
  assert.equal(f.client.value.pendingCommandId, currentId); assert.equal(f.client.value.error, null);
  assert.equal(f.client.value.transcript.length, 1); assert.equal(f.client.value.transcript[0].text, 'new change');
  f.client.dispose();
});

test('a missing command remains locked until server time proves its persisted expiry, including reload', async () => {
  const f = setup(), storage = memoryStorage();
  const first = new VoiceCompanion(f.relay, f.speech, { userId: 'durable-owner', storage });
  await first.pair(); f.setFailure(new TypeError('Request did not reach the server'));
  await first.submit('utterance', { text: 'quiet vocal' }); const commandId = first.value.pendingCommandId;
  const saved = JSON.parse(storage.getItem('mixroom.voice.v2.https%3A%2F%2Frelay.test%2Fapi%2Fvoice.durable-owner')!);
  assert.equal(typeof saved.expiresAt, 'string'); first.dispose();
  const restored = new VoiceCompanion(f.relay, f.speech, { userId: 'durable-owner', storage });
  for (const serverDate of [undefined, Date.parse(saved.expiresAt) - 1]) {
    f.relay.status = async () => { throw new RelayError('Missing', 404, 'command_not_found', serverDate); };
    await restored.tick(); assert.equal(restored.value.pendingCommandId, commandId);
  }
  f.relay.status = async () => { throw new RelayError('Missing', 404, 'command_not_found', Date.parse(saved.expiresAt) + 1000); };
  await restored.tick(); assert.equal(restored.value.pendingCommandId, null);
  assert.match(restored.value.error!, /expired before the server received/);
  assert.equal(f.calls.filter(x => x === 'submit').length, 1); restored.dispose(); f.client.dispose();
});

test('legacy recovery without an expiry never guesses that an unknown command did not run', async () => {
  const f = setup(), storage = memoryStorage();
  storage.setItem('mixroom.voice.v2.https%3A%2F%2Frelay.test%2Fapi%2Fvoice.legacy', JSON.stringify({ sessionId: 'session', commandId: 'unknown-command' }));
  const restored = new VoiceCompanion(f.relay, f.speech, { userId: 'legacy', storage });
  f.relay.status = async () => { throw new RelayError('Missing', 404, 'command_not_found', Date.now() + 1_000_000); };
  await restored.tick(); assert.equal(restored.value.pendingCommandId, 'unknown-command'); assert.equal(f.calls.includes('submit'), false);
  restored.dispose(); f.client.dispose();
});

test('emergency cancellation during final microphone release prevents readiness and sends stop immediately', async () => {
  const f = setup(); await f.client.pair();
  f.state.state.recordingPhase = 'awaiting_ready'; f.state.state.captureId = 'capture';
  await f.client.tick(); await setImmediate();
  const release = deferred<void>(); f.speech.stopListening = () => release.promise;
  f.finishSpeech(); await setImmediate(); // Final readiness release is now waiting.
  const stopped = f.client.emergencyStop(); await setImmediate();
  assert.ok(f.calls.includes('emergency')); assert.equal(f.calls.includes('ready'), false);
  release.resolve(); await stopped; await setImmediate(); assert.equal(f.calls.includes('ready'), false);
  f.client.dispose();
});

test('a delayed audio response cannot play after conversation stop', async () => {
  const f = setup(); await f.client.pair(); await f.client.startConversation();
  const audio = deferred<Response>(); f.relay.tts = () => audio.promise;
  await f.client.submit('utterance', { text: 'quieter vocal' }); f.complete(); await f.client.tick(); await setImmediate();
  await f.client.stopConversation(); audio.resolve(new Response('old response')); await setImmediate();
  assert.equal(f.calls.includes('speak'), false); assert.equal(f.client.value.phase, 'idle'); f.client.dispose();
});

test('polling continues while automatically resumed microphone setup is pending', async () => {
  const f = setup(); await f.client.pair(); await f.client.startConversation();
  f.state.nativeConnected = false; await f.client.tick(); f.state.nativeConnected = true;
  const setupPending = deferred<void>(); f.speech.listen = () => setupPending.promise;
  await f.client.tick(); const previous = f.calls.filter(x => x === 'presence').length;
  await f.client.tick(); assert.ok(f.calls.filter(x => x === 'presence').length > previous);
  setupPending.resolve(); await setImmediate(); f.client.dispose();
});

test('session revocation does not wait for an unresolved microphone permission dialog', async () => {
  const f = setup(); await f.client.pair(); const release = deferred<void>();
  f.speech.stopListening = () => release.promise;
  const ended = f.client.endSession(); await setImmediate(); assert.ok(f.calls.includes('revoke'));
  release.resolve(); await ended; assert.equal(f.client.value.sessionId, null); f.client.dispose();
});

test('relay errors retain authoritative server time only when its Date header is valid', async () => {
  for (const date of ['Thu, 01 Oct 2026 06:00:00 GMT', 'invalid']) {
    const relay = new VoiceRelay('https://example.test', async () => 'session-access', async () => Response.json({ error: { code: 'command_not_found', message: 'Missing' } }, { status: 404, headers: { Date: date } }));
    await assert.rejects(relay.status('session', 'command'), error => error instanceof RelayError && (date === 'invalid' ? error.serverDate === undefined : error.serverDate === Date.parse(date)));
  }
});

test('two backends with the same owner never share pending command recovery', async () => {
  const f = setup(), storage = memoryStorage();
  const first = new VoiceCompanion(f.relay, f.speech, { userId: 'owner', storage });
  await first.pair(); await first.submit('utterance', { text: 'First studio command' });
  const otherRelay = { ...f.relay, baseUrl: 'https://different-studio.test/api/voice' } as VoiceRelay;
  const other = new VoiceCompanion(otherRelay, f.speech, { userId: 'owner', storage });
  assert.equal(other.value.sessionId, null); assert.equal(other.value.pendingCommandId, null);
  const same = new VoiceCompanion({ ...f.relay, baseUrl: 'https://RELAY.test:443/api/voice/' } as VoiceRelay, f.speech, { userId: 'owner', storage });
  assert.equal(same.value.sessionId, first.value.sessionId); assert.equal(same.value.pendingCommandId, first.value.pendingCommandId);
  first.dispose(); other.dispose(); same.dispose(); f.client.dispose();
});

test('unscoped legacy recovery cannot attach to an arbitrary local backend', () => {
  const f = setup(), storage = memoryStorage();
  storage.setItem('mixroom.voice.owner', JSON.stringify({ sessionId: 'another-backend', commandId: 'uncertain-command' }));
  const client = new VoiceCompanion(f.relay, f.speech, { userId: 'owner', storage });
  assert.equal(client.value.sessionId, null); assert.equal(client.value.pendingCommandId, null);
  client.dispose(); f.client.dispose();
});

test('authoritative missing session permits local disconnect without replaying or claiming success', async () => {
  const f = setup(); await f.client.pair(); await f.client.submit('utterance', { text: 'An uncertain change' });
  f.relay.state = async () => { throw new RelayError('Session missing', 404, 'session_not_found'); };
  await f.client.tick();
  assert.equal(f.client.value.sessionId, null); assert.equal(f.client.value.pendingCommandId, null);
  assert.match(f.client.value.error!, /unknown outcome/); assert.doesNotMatch(f.client.value.error!, /not applied/);
  assert.equal(f.calls.filter(call => call === 'submit').length, 1); assert.equal(f.calls.includes('emergency'), false);
  f.client.dispose();
});

test('expired or revoked session can be disconnected while a native take remains untouched', async () => {
  for (const code of ['session_expired_or_revoked', 'session_expired', 'session_revoked']) {
    const f = setup(); await f.client.pair();
    f.state.state.recordingPhase = 'capturing'; f.state.state.captureId = 'native-take'; await f.client.tick();
    f.relay.revoke = async () => { throw new RelayError('Unavailable', 410, code); };
    await f.client.endSession();
    assert.equal(f.client.value.sessionId, null); assert.match(f.client.value.error!, /unknown outcome/);
    assert.equal(f.calls.includes('emergency'), false); assert.equal(f.calls.includes('submit'), false);
    f.client.dispose();
  }
});

test('an unrelated 404 does not discard an uncertain session', async () => {
  const f = setup(); await f.client.pair();
  f.relay.revoke = async () => { throw new RelayError('Proxy not found', 404, 'service_error'); };
  await f.client.endSession(); assert.equal(f.client.value.sessionId, 'session'); f.client.dispose();
});
