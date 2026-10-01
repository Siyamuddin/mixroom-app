import { AudioFormat, CommitStrategy, RealtimeEvents, Scribe } from '@elevenlabs/client';
import type { SpeechPort } from './session.ts';

type Connection = ReturnType<typeof Scribe.connect>;
export type SpeechDependencies = {
  connect: typeof Scribe.connect;
  getUserMedia: (constraints: MediaStreamConstraints) => Promise<MediaStream>;
  audioContext: () => AudioContext;
  worklet: (context: AudioContext) => AudioWorkletNode;
  audio: () => HTMLAudioElement;
  mediaSource: () => MediaSource;
  supportsStreaming: () => boolean;
  objectUrl: (value: Blob | MediaSource) => string;
  revokeUrl: (url: string) => void;
};
type Capture = {
  abort: AbortController; start?: Promise<void>; closing?: Promise<void>;
  stream?: MediaStream; context?: AudioContext; connection?: Connection;
  source?: MediaStreamAudioSourceNode; worklet?: AudioWorkletNode; gain?: GainNode;
  removeListeners: (() => void)[];
};
type Playback = {
  abort: AbortController; audio: HTMLAudioElement; done: boolean; url?: string;
  reader?: ReadableStreamDefaultReader<Uint8Array>; timer?: ReturnType<typeof setTimeout>;
  resolve: () => void; reject: (error: Error) => void;
};

// Capture stays local except for the transient PCM frames sent to Scribe. We own
// the tracks, rather than SDK microphone mode, so shutdown can await acquisition.
const PCM_WORKLET = `
class MixRoomPcm extends AudioWorkletProcessor {
  constructor() { super(); this.samples = new Int16Array(2048); this.offset = 0; }
  process(inputs) {
    const channels = inputs[0];
    if (!channels || !channels.length) return true;
    for (let i = 0; i < channels[0].length; i++) {
      let value = 0;
      for (const channel of channels) value += channel[i] || 0;
      value = Math.max(-1, Math.min(1, value / channels.length));
      this.samples[this.offset++] = value < 0 ? value * 32768 : value * 32767;
      if (this.offset === this.samples.length) {
        this.port.postMessage(this.samples.buffer, [this.samples.buffer]);
        this.samples = new Int16Array(2048); this.offset = 0;
      }
    }
    return true;
  }
}
registerProcessor('mixroom-pcm', MixRoomPcm);
`;

const defaults: SpeechDependencies = {
  connect: options => Scribe.connect(options),
  getUserMedia: constraints => {
    if (!globalThis.navigator?.mediaDevices?.getUserMedia) throw new Error('Microphone access requires HTTPS and a supported browser.');
    return navigator.mediaDevices.getUserMedia(constraints);
  },
  audioContext: () => new AudioContext({ sampleRate: 16000 }),
  worklet: context => new AudioWorkletNode(context, 'mixroom-pcm'),
  audio: () => new Audio(),
  mediaSource: () => new MediaSource(),
  supportsStreaming: () => typeof MediaSource !== 'undefined' && MediaSource.isTypeSupported('audio/mpeg'),
  objectUrl: value => URL.createObjectURL(value),
  revokeUrl: url => URL.revokeObjectURL(url),
};

/** Stable transport adapter. Intentional stops settle pending operations. */
export class ElevenSpeechPort implements SpeechPort {
  private readonly deps: SpeechDependencies;
  private capture?: Capture;
  private pendingClosures = new Set<Promise<void>>();
  private playback?: Playback;

  constructor(dependencies: Partial<SpeechDependencies> = {}) { this.deps = { ...defaults, ...dependencies }; }

  async listen(token: string, partial: (text: string) => void, committed: (text: string) => void, error: (message: string) => void): Promise<void> {
    const previous = this.stopListening();
    const capture: Capture = { abort: new AbortController(), removeListeners: [] };
    this.capture = capture;
    capture.start = this.startCapture(capture, previous, token, partial, committed, error);
    try { await capture.start; }
    catch (cause) {
      const canceled = capture.abort.signal.aborted;
      if (this.capture === capture) this.capture = undefined;
      await this.closeCapture(capture);
      if (!canceled) throw asError(cause);
    }
  }

  private async startCapture(c: Capture, previous: Promise<void>, token: string, partial: (text: string) => void, committed: (text: string) => void, report: (message: string) => void) {
    await previous;
    if (c.abort.signal.aborted) return;
    // Do not race this promise with abort: a late permission grant must be stopped
    // and awaited before the caller can acknowledge native recording readiness.
    c.stream = await this.deps.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false });
    if (c.abort.signal.aborted) { c.stream.getTracks().forEach(track => track.stop()); return; }
    c.context = this.deps.audioContext();
    const sampleRate = c.context.sampleRate;
    const audioFormat = ({ 8000: AudioFormat.PCM_8000, 16000: AudioFormat.PCM_16000, 22050: AudioFormat.PCM_22050,
      24000: AudioFormat.PCM_24000, 44100: AudioFormat.PCM_44100, 48000: AudioFormat.PCM_48000 } as Record<number, AudioFormat>)[sampleRate];
    if (!audioFormat) throw new Error('This microphone sample rate is not supported. Choose another audio device.');
    const moduleUrl = this.deps.objectUrl(new Blob([PCM_WORKLET], { type: 'application/javascript' }));
    try { await abortable(c.context.audioWorklet.addModule(moduleUrl), c.abort.signal); }
    finally { this.deps.revokeUrl(moduleUrl); }
    if (c.abort.signal.aborted) return;
    c.worklet = this.deps.worklet(c.context);
    c.source = c.context.createMediaStreamSource(c.stream);
    c.gain = c.context.createGain(); c.gain.gain.value = 0;
    c.worklet.connect(c.gain); c.gain.connect(c.context.destination);
    const connection = c.connection = this.deps.connect({ token, modelId: 'scribe_v2_realtime', audioFormat, sampleRate,
      commitStrategy: CommitStrategy.VAD, vadSilenceThresholdSecs: 0.7 });
    let started = false;
    let failed = false;
    let resolveReady!: () => void, rejectReady!: (error: Error) => void;
    const ready = new Promise<void>((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
    const active = () => this.capture === c && !c.abort.signal.aborted;
    const fail = (message: string) => {
      if (!active() || failed) return;
      failed = true;
      if (!started) rejectReady(new Error(message));
      else {
        void this.stopListening().catch(() => undefined);
        report(message);
      }
    };
    const onStarted = () => { if (active()) resolveReady(); };
    const onPartial = (data: { text: string }) => { if (active()) partial(data.text); };
    const onCommitted = (data: { text: string }) => { if (active()) committed(data.text); };
    const onError = () => fail('Voice recognition disconnected. Check your connection and try starting again.');
    const onClose = () => fail('Voice recognition ended. Start the conversation again when ready.');
    connection.on(RealtimeEvents.SESSION_STARTED, onStarted);
    connection.on(RealtimeEvents.PARTIAL_TRANSCRIPT, onPartial);
    connection.on(RealtimeEvents.COMMITTED_TRANSCRIPT, onCommitted);
    connection.on(RealtimeEvents.ERROR, onError);
    connection.on(RealtimeEvents.CLOSE, onClose);
    c.removeListeners.push(() => {
      connection.off(RealtimeEvents.SESSION_STARTED, onStarted);
      connection.off(RealtimeEvents.PARTIAL_TRANSCRIPT, onPartial);
      connection.off(RealtimeEvents.COMMITTED_TRANSCRIPT, onCommitted);
      connection.off(RealtimeEvents.ERROR, onError);
      connection.off(RealtimeEvents.CLOSE, onClose);
    });
    for (const track of c.stream.getTracks()) {
      const ended = () => fail('The microphone was disconnected. Reconnect it and start again.');
      track.addEventListener('ended', ended);
      c.removeListeners.push(() => track.removeEventListener('ended', ended));
    }
    c.worklet.port.onmessage = (event: MessageEvent<ArrayBuffer>) => {
      if (!active() || !started) return;
      try { connection.send({ audioBase64: base64Pcm(event.data), sampleRate }); }
      catch { fail('Voice recognition disconnected. Start the conversation again.'); }
    };
    const timer = setTimeout(() => rejectReady(new Error('Voice recognition took too long to connect. Please try again.')), 20_000);
    try { await abortable(ready, c.abort.signal); }
    finally { clearTimeout(timer); }
    if (!active()) return;
    // From here a disconnect is a runtime failure, including while resume()
    // waits for browser audio permission. Abort it rather than leaving it pending.
    started = true;
    await abortable(c.context.resume(), c.abort.signal);
    if (!active()) return;
    c.source.connect(c.worklet);
  }

  stopListening(): Promise<void> {
    const current = this.capture; this.capture = undefined;
    if (current) this.closeCapture(current);
    // A second stop still waits for a permission request canceled by the first.
    return Promise.all([...this.pendingClosures]).then(() => undefined);
  }

  private closeCapture(c: Capture): Promise<void> {
    if (c.closing) return c.closing;
    c.abort.abort();
    const release = () => {
      c.removeListeners.splice(0).forEach(remove => remove());
      c.stream?.getTracks().forEach(track => track.stop());
      if (c.worklet) { c.worklet.port.onmessage = null; c.worklet.port.close(); c.worklet.disconnect(); }
      c.source?.disconnect(); c.gain?.disconnect();
      c.connection?.close(); c.connection = undefined;
    };
    release();
    c.closing = (async () => {
      await c.start?.catch(() => undefined);
      release();
      if (c.context && c.context.state !== 'closed') await c.context.close();
    })();
    this.pendingClosures.add(c.closing);
    void c.closing.then(() => this.pendingClosures.delete(c.closing!), () => this.pendingClosures.delete(c.closing!));
    return c.closing;
  }

  speak(response: Response): Promise<void> {
    this.stopSpeaking();
    if (!response.ok) return Promise.reject(new Error('The audio response is unavailable.'));
    const audio = this.deps.audio();
    let resolve!: () => void, reject!: (error: Error) => void;
    const completed = new Promise<void>((yes, no) => { resolve = yes; reject = no; });
    const p: Playback = { abort: new AbortController(), audio, done: false, resolve, reject };
    this.playback = p;
    audio.onended = () => this.finishPlayback(p);
    audio.onerror = () => this.finishPlayback(p, new Error('This browser could not play the voice response.'));
    p.timer = setTimeout(() => this.finishPlayback(p, new Error('The audio response timed out. Please try again.')), 120_000);
    void this.playResponse(p, response).catch(cause => { if (!p.done) this.finishPlayback(p, asError(cause)); });
    return completed;
  }

  private async playResponse(p: Playback, response: Response) {
    if (!response.body) throw new Error('The voice response was empty.');
    p.reader = response.body.getReader();
    let source: MediaSource | undefined, buffer: SourceBuffer | undefined;
    if (this.deps.supportsStreaming()) {
      try {
        source = this.deps.mediaSource();
        const open = eventOnce(source, 'sourceopen', p.abort.signal, 'sourceclose');
        p.url = this.deps.objectUrl(source); p.audio.src = p.url;
        await open;
        if (p.done) return;
        buffer = source.addSourceBuffer('audio/mpeg');
      } catch (cause) {
        if (p.done) return;
        // Fall back before consuming the stream on browsers without MP3 MSE.
        source = undefined;
        if (p.url) this.deps.revokeUrl(p.url);
        p.url = undefined; p.audio.removeAttribute('src');
        if (p.abort.signal.aborted) throw cause;
      }
    }
    const chunks: Uint8Array<ArrayBuffer>[] = [];
    let bytes = 0, playing = false;
    while (!p.done) {
      const { done, value } = await p.reader.read();
      if (p.done) return;
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 12_000_000) throw new Error('The voice response was too long.');
      if (buffer) {
        const appended = eventOnce(buffer, 'updateend', p.abort.signal, 'error');
        try { buffer.appendBuffer(new Uint8Array(value)); }
        catch (cause) { p.abort.abort(); await appended.catch(() => undefined); throw cause; }
        await appended;
        if (p.done) return;
        if (!playing) { playing = true; this.startPlayback(p); }
      } else chunks.push(new Uint8Array(value));
    }
    if (p.done) return;
    if (!bytes) throw new Error('The voice response was empty.');
    if (source && buffer) {
      if (source.readyState === 'open') source.endOfStream();
    } else {
      p.url = this.deps.objectUrl(new Blob(chunks, { type: 'audio/mpeg' }));
      p.audio.src = p.url; this.startPlayback(p);
    }
  }

  private startPlayback(p: Playback) {
    void p.audio.play().catch(() => {
      if (!p.done) this.finishPlayback(p, new Error('Allow audio playback in this browser, then start the conversation again.'));
    });
  }

  private finishPlayback(p: Playback, error?: Error) {
    if (p.done) return;
    p.done = true; p.abort.abort(); clearTimeout(p.timer);
    void p.reader?.cancel().catch(() => undefined);
    p.audio.onended = null; p.audio.onerror = null;
    p.audio.pause(); p.audio.removeAttribute('src'); p.audio.load();
    if (p.url) this.deps.revokeUrl(p.url);
    if (this.playback === p) this.playback = undefined;
    if (error) p.reject(error); else p.resolve();
  }

  stopSpeaking(): void { if (this.playback) this.finishPlayback(this.playback); }
}

function base64Pcm(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function asError(value: unknown): Error { return value instanceof Error ? value : new Error('Audio is unavailable. Please try again.'); }
function abortable<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise((resolve, reject) => {
    const canceled = () => reject(new DOMException('Audio operation stopped.', 'AbortError'));
    if (signal.aborted) { void promise.catch(() => undefined); canceled(); return; }
    signal.addEventListener('abort', canceled, { once: true });
    promise.then(resolve, reject).finally(() => signal.removeEventListener('abort', canceled));
  });
}
function eventOnce(target: EventTarget, event: string, signal: AbortSignal, failure?: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const cleanup = () => { target.removeEventListener(event, success); if (failure) target.removeEventListener(failure, failed); signal.removeEventListener('abort', canceled); };
    const success = () => { cleanup(); resolve(); };
    const failed = () => { cleanup(); reject(new Error('Audio streaming is unavailable.')); };
    const canceled = () => { cleanup(); reject(new DOMException('Audio operation stopped.', 'AbortError')); };
    if (signal.aborted) { canceled(); return; }
    target.addEventListener(event, success, { once: true });
    if (failure) target.addEventListener(failure, failed, { once: true });
    signal.addEventListener('abort', canceled, { once: true });
  });
}
