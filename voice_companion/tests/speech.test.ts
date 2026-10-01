// Offline browser-resource doubles exercise lifecycle ordering; these tests do
// not prove real microphone permission, codec support, or ElevenLabs connectivity.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers/promises';
import { ElevenSpeechPort, type SpeechDependencies } from '../src/voice/speech.ts';

function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (cause: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
class Track extends EventTarget {
  stopped = false;
  stop() { this.stopped = true; }
}
class Connection {
  listeners = new Map<string, Set<Function>>(); closed = false; frames: unknown[] = [];
  on(name: string, listener: Function) { if (!this.listeners.has(name)) this.listeners.set(name, new Set()); this.listeners.get(name)!.add(listener); }
  off(name: string, listener: Function) { this.listeners.get(name)?.delete(listener); }
  emit(name: string, data?: unknown) { this.listeners.get(name)?.forEach(listener => listener(data)); }
  send(data: unknown) { this.frames.push(data); }
  close() { this.closed = true; this.emit('close'); }
}
class AudioDouble {
  src = ''; onended: (() => void) | null = null; onerror: (() => void) | null = null;
  plays = 0; pauses = 0; failPlay = false;
  async play() { this.plays++; if (this.failPlay) throw new Error('blocked'); }
  pause() { this.pauses++; }
  removeAttribute() { this.src = ''; }
  load() {}
}
class BufferDouble extends EventTarget {
  chunks: Uint8Array[] = [];
  appendBuffer(value: Uint8Array) { this.chunks.push(value); queueMicrotask(() => this.dispatchEvent(new Event('updateend'))); }
}
class MediaSourceDouble extends EventTarget {
  readyState = 'open'; buffer = new BufferDouble(); ended = false; failAdd = false;
  addSourceBuffer() { if (this.failAdd) throw new Error('not supported'); return this.buffer; }
  endOfStream() { this.ended = true; }
}
function fixture() {
  const track = new Track(), connection = new Connection();
  const stream = { getTracks: () => [track] } as unknown as MediaStream;
  const worklet = { connect() {}, disconnect() {}, port: { onmessage: null as Function | null, close() {} } };
  let closeContext = async () => {};
  const context = { sampleRate: 16000, state: 'running', audioWorklet: { async addModule() {} }, destination: {},
    createMediaStreamSource: () => ({ connect() {}, disconnect() {} }),
    createGain: () => ({ gain: { value: 1 }, connect() {}, disconnect() {} }),
    async resume() {}, async close() { await closeContext(); context.state = 'closed'; },
  };
  const audios: AudioDouble[] = [], sources: MediaSourceDouble[] = [], urls: unknown[] = [], revoked: string[] = [];
  let connectionOptions: unknown;
  const deps: Partial<SpeechDependencies> = {
    getUserMedia: async () => stream,
    audioContext: () => context as unknown as AudioContext,
    worklet: () => worklet as unknown as AudioWorkletNode,
    connect: options => { connectionOptions = options; queueMicrotask(() => connection.emit('session_started')); return connection as any; },
    audio: () => { const a = new AudioDouble(); audios.push(a); return a as unknown as HTMLAudioElement; },
    mediaSource: () => { const source = new MediaSourceDouble(); sources.push(source); return source as unknown as MediaSource; },
    supportsStreaming: () => false,
    objectUrl: value => { urls.push(value); if (value instanceof MediaSourceDouble) queueMicrotask(() => value.dispatchEvent(new Event('sourceopen'))); return `blob:fake/${urls.length}`; },
    revokeUrl: url => revoked.push(url),
  };
  return { deps, track, stream, connection, context, worklet, audios, sources, urls, revoked,
    options: () => connectionOptions, closeContext: (promise: Promise<void>) => { closeContext = () => promise; } };
}

test('stopping while microphone permission is pending awaits and releases a late grant, including repeated stop calls', async () => {
  const f = fixture(), microphone = deferred<MediaStream>(); f.deps.getUserMedia = () => microphone.promise;
  const speech = new ElevenSpeechPort(f.deps);
  const listening = speech.listen('temporary', () => {}, () => {}, () => {});
  await setImmediate();
  let stopped = false;
  const first = speech.stopListening(); const second = speech.stopListening().then(() => { stopped = true; });
  await setImmediate(); assert.equal(stopped, false);
  microphone.resolve(f.stream); await Promise.all([first, second, listening]);
  assert.equal(f.track.stopped, true); assert.equal(f.options(), undefined);
});

test('recognition uses VAD, stops tracks immediately, awaits audio cleanup and ignores late transcripts', async () => {
  const f = fixture(), closing = deferred<void>(); f.closeContext(closing.promise);
  const speech = new ElevenSpeechPort(f.deps), heard: string[] = [];
  await speech.listen('temporary', text => heard.push(text), text => heard.push(text), () => {});
  assert.equal((f.options() as any).commitStrategy, 'vad'); assert.equal((f.options() as any).microphone, undefined);
  f.connection.emit('partial_transcript', { text: 'lower' });
  const late = [...f.connection.listeners.get('committed_transcript')!][0];
  f.worklet.port.onmessage!({ data: new Int16Array([0, 100, -100]).buffer });
  assert.equal(f.connection.frames.length, 1);
  let finished = false; const stopping = speech.stopListening().then(() => { finished = true; });
  assert.equal(f.track.stopped, true); assert.equal(f.connection.closed, true);
  late({ text: 'late command' }); await setImmediate(); assert.equal(finished, false);
  assert.deepEqual(heard, ['lower']);
  closing.resolve(); await stopping; assert.equal(f.context.state, 'closed');
});

test('microphone permission failures reject setup without creating a paid connection', async () => {
  const f = fixture(); f.deps.getUserMedia = async () => { throw new DOMException('Permission denied', 'NotAllowedError'); };
  const speech = new ElevenSpeechPort(f.deps);
  await assert.rejects(speech.listen('temporary', () => {}, () => {}, () => {}), /Permission denied/);
  await speech.stopListening(); assert.equal(f.options(), undefined);
});

test('streamed MP3 starts playback before response EOF and settles only after audio ends', async () => {
  const f = fixture(); f.deps.supportsStreaming = () => true;
  const speech = new ElevenSpeechPort(f.deps); let controller!: ReadableStreamDefaultController<Uint8Array>;
  const response = new Response(new ReadableStream<Uint8Array>({ start(value) { controller = value; } }));
  let finished = false; const speaking = speech.speak(response).then(() => { finished = true; });
  controller.enqueue(new Uint8Array([1, 2, 3])); await setImmediate();
  assert.equal(f.audios[0].plays, 1); assert.equal(f.sources[0].ended, false); assert.equal(finished, false);
  controller.enqueue(new Uint8Array([4, 5])); controller.close(); await setImmediate();
  assert.equal(f.sources[0].buffer.chunks.length, 2); assert.equal(f.sources[0].ended, true); assert.equal(finished, false);
  f.audios[0].onended!(); await speaking; assert.equal(finished, true); assert.equal(f.revoked.length, 1);
});

test('unsupported MP3 MediaSource falls back to a complete Blob and releases its URL', async () => {
  const f = fixture(); f.deps.supportsStreaming = () => true;
  f.deps.mediaSource = () => { const s = new MediaSourceDouble(); s.failAdd = true; return s as unknown as MediaSource; };
  const speech = new ElevenSpeechPort(f.deps); const speaking = speech.speak(new Response(new Uint8Array([1, 2, 3])));
  await setImmediate(); assert.equal(f.audios[0].plays, 1); assert.ok(f.urls.at(-1) instanceof Blob);
  f.audios[0].onended!(); await speaking; assert.equal(f.revoked.length, 2);
});

test('stopSpeaking cancels a stalled body and resolves playback so recording readiness cannot hang', async () => {
  const f = fixture(), speech = new ElevenSpeechPort(f.deps); let canceled = false;
  const speaking = speech.speak(new Response(new ReadableStream({ cancel() { canceled = true; } })));
  await setImmediate(); speech.stopSpeaking(); await speaking;
  assert.equal(canceled, true); assert.equal(f.audios[0].pauses, 1); assert.equal(f.audios[0].plays, 0);
});

test('stopSpeaking also releases a pending MediaSource open', async () => {
  const f = fixture(); f.deps.supportsStreaming = () => true;
  f.deps.objectUrl = () => 'blob:never-opens';
  const speech = new ElevenSpeechPort(f.deps), speaking = speech.speak(new Response('audio'));
  speech.stopSpeaking(); await speaking; await setImmediate();
  assert.equal(f.audios[0].plays, 0); assert.deepEqual(f.revoked, ['blob:never-opens']);
});

test('blocked autoplay rejects with an actionable error and frees response resources', async () => {
  const f = fixture(); f.deps.audio = () => { const a = new AudioDouble(); a.failPlay = true; f.audios.push(a); return a as unknown as HTMLAudioElement; };
  const speech = new ElevenSpeechPort(f.deps);
  await assert.rejects(speech.speak(new Response('audio')), /Allow audio playback/);
  assert.equal(f.audios[0].pauses, 1); assert.equal(f.revoked.length, 1);
});
