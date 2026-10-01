import { RelayError, type VoiceRelay, type SessionSnapshot, type CommandEnvelope, type CommandResult } from './relay.ts';

export interface SpeechPort {
  listen(token: string, partial: (text: string) => void, committed: (text: string) => void, error: (message: string) => void): Promise<void>;
  stopListening(): Promise<void>;
  speak(response: Response): Promise<void>;
  stopSpeaking(): void;
}
export type CompanionState = {
  sessionId: string | null; pairingCode: string | null; pairingExpiresAt: string | null;
  snapshot: SessionSnapshot | null; phase: 'idle' | 'connecting' | 'listening' | 'working' | 'speaking' | 'recording';
  partial: string; transcript: { id: string; role: 'you' | 'mixroom'; text: string; outcome?: string }[];
  error: string | null; pendingCommandId: string | null; conversation: boolean;
  latency: { recognitionMs?: number; responseMs?: number };
};
/** One command owner in the browser. Unknown outcomes are never resubmitted. */
export class VoiceCompanion {
  readonly relay: VoiceRelay; readonly speech: SpeechPort;
  private listeners = new Set<() => void>();
  private pollOwner: symbol | null = null;
  private recognizing = false; private disposed = false; private generation = 0;
  private inputEpoch = 0; private outputEpoch = 0;
  private pairing = false; private ending = false;
  private handlingCapture: string | null = null; private readyCaptures = new Set<string>(); private canceledCaptures = new Set<string>();
  private outputBusy = false;
  private commandStarted = 0; private pendingExpiresAt: string | null = null;
  private speechStarted = 0; private outputAbort?: AbortController;
  private storage?: Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
  private storageKey: string;
  value: CompanionState = {
    sessionId: null, pairingCode: null, pairingExpiresAt: null, snapshot: null, phase: 'idle', partial: '',
    transcript: [], error: null, pendingCommandId: null, conversation: false, latency: {},
  };
  constructor(relay: VoiceRelay, speech: SpeechPort, options: { userId: string; storage?: Pick<Storage, 'getItem' | 'setItem' | 'removeItem'> }) {
    this.relay = relay; this.speech = speech; this.storage = options.storage;
    const studio = new URL(relay.baseUrl).href.replace(/\/$/, '');
    // Local installations all use owner ID "owner". Recovery is scoped to both
    // the normalized backend URL and owner; old unscoped records are ignored.
    this.storageKey = `mixroom.voice.v2.${encodeURIComponent(studio)}.${encodeURIComponent(options.userId)}`;
    try {
      const saved = JSON.parse(this.storage?.getItem(this.storageKey) ?? 'null');
      if (typeof saved?.sessionId === 'string' && saved.sessionId) {
        const commandId = typeof saved.commandId === 'string' && saved.commandId ? saved.commandId : null;
        this.value = { ...this.value, sessionId: saved.sessionId, pendingCommandId: commandId };
        this.pendingExpiresAt = commandId && typeof saved.expiresAt === 'string' && Number.isFinite(Date.parse(saved.expiresAt)) ? saved.expiresAt : null;
        this.commandStarted = typeof saved.commandStarted === 'number' && Number.isFinite(saved.commandStarted) ? saved.commandStarted : 0;
      }
    } catch { try { this.storage?.removeItem(this.storageKey); } catch { /* Storage may be unavailable. */ } }
  }
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  snapshot = () => this.value;
  private update(patch: Partial<CompanionState>) { if (this.disposed) return; this.value = { ...this.value, ...patch }; this.listeners.forEach(f => f()); }
  private current(generation: number, sessionId?: string | null) { return !this.disposed && generation === this.generation && (sessionId === undefined || sessionId === this.value.sessionId); }
  private remember() {
    try {
      this.storage?.setItem(this.storageKey, JSON.stringify({ sessionId: this.value.sessionId, commandId: this.value.pendingCommandId, expiresAt: this.pendingExpiresAt, commandStarted: this.commandStarted }));
      return true;
    } catch { this.update({ error: 'This browser cannot save request recovery information. No new request was sent.' }); return false; }
  }
  private clearPending() { this.pendingExpiresAt = null; this.commandStarted = 0; this.update({ pendingCommandId: null }); this.remember(); }
  private forgetSession(error: string | null) {
    this.generation++; this.inputEpoch++; this.recognizing = false;
    this.pollOwner = null; this.pairing = false; this.ending = false; this.handlingCapture = null;
    this.stopOutput(); void this.speech.stopListening().catch(() => {});
    try { this.storage?.removeItem(this.storageKey); } catch { /* Unavailable storage must not trap the disconnected UI. */ }
    this.readyCaptures.clear(); this.canceledCaptures.clear(); this.pendingExpiresAt = null; this.commandStarted = 0;
    this.update({ sessionId: null, snapshot: null, pairingCode: null, pendingCommandId: null, pairingExpiresAt: null,
      phase: 'idle', conversation: false, partial: '', transcript: [], latency: {}, error });
  }
  private forgetUnavailableSession() {
    const uncertain = !!this.value.pendingCommandId || this.capturing;
    this.forgetSession(uncertain
      ? 'This studio session is no longer available. Any unfinished command has an unknown outcome. Check your Mac before continuing; a take may still be recording there.'
      : 'This studio session is no longer available. Pair your Mac again to continue.');
  }
  private line(role: 'you' | 'mixroom', text: string, outcome?: string) { this.update({ transcript: [...this.value.transcript, { id: crypto.randomUUID(), role, text, outcome }].slice(-50) }); }
  get connected() { return !this.disposed && !this.ending && this.value.snapshot?.status === 'active' && this.value.snapshot.nativeConnected && this.value.snapshot.state.projectReady === true; }
  private get capturing() { const phase = this.value.snapshot?.state.recordingPhase; return !!phase && phase !== 'idle'; }
  async pair() {
    if (this.disposed || this.pairing || this.ending) return;
    if (this.value.sessionId) { this.update({ error: 'End the current session before pairing another Mac.' }); return; }
    this.pairing = true; const generation = this.generation;
    this.update({ phase: 'connecting', error: null });
    try {
      const pairing = await this.relay.createPairing();
      if (!this.current(generation)) return;
      this.update({ sessionId: pairing.sessionId, pairingCode: pairing.pairingCode, pairingExpiresAt: pairing.expiresAt, phase: 'idle' });
      this.remember(); await this.tick();
    } catch (e) { if (this.current(generation)) this.update({ phase: 'idle', error: message(e) }); }
    finally { if (this.current(generation)) this.pairing = false; }
  }
  async tick() {
    const id = this.value.sessionId; if (!id || this.pollOwner || this.disposed || this.ending) return;
    const generation = this.generation; const owner = Symbol(); this.pollOwner = owner;
    try {
      await this.relay.presence(id);
      if (!this.current(generation, id)) return;
      const state = await this.relay.state(id);
      if (!this.current(generation, id)) return;
      if (state.sessionId !== id) throw new Error('The relay returned a different session. Reconnect your studio.');
      this.update({ snapshot: state });
      if (!this.connected) { await this.pauseInput(); if (this.current(generation, id)) this.update({ phase: 'idle' }); }
      if (!this.current(generation, id)) return;
      const pending = this.value.pendingCommandId;
      if (pending) {
        try {
          const status = await this.relay.status(id, pending);
          if (!this.current(generation, id) || pending !== this.value.pendingCommandId) return;
          if (status.result && !['queued', 'running'].includes(status.status)) await this.complete(status.result);
          else if (this.commandStarted && Date.now() - this.commandStarted > 150_000) {
            this.update({ error: 'This request is taking longer than expected. Its status is still being checked; it will not be sent again.' });
          }
        } catch (e) {
          if (!this.current(generation, id) || pending !== this.value.pendingCommandId) return;
          if (e instanceof RelayError && e.status === 404 && e.code === 'command_not_found') {
            // A missing row alone is not proof: the original POST may still arrive.
            // Only authoritative server time beyond the immutable envelope expiry
            // proves that a later arrival cannot execute. Never resubmit this ID.
            if (this.pendingExpiresAt && e.serverDate !== undefined && e.serverDate >= Date.parse(this.pendingExpiresAt)) {
              this.clearPending(); this.update({ phase: 'idle', error: 'The request expired before the server received it. No action was applied. You can give a new command.' });
            } else this.update({ error: 'The server has not confirmed this request. Checking its status without sending it again.' });
          } else throw e;
        }
      }
      if (!this.current(generation, id)) return;
      const captureId = state.state.captureId;
      if (this.connected && state.state.recordingPhase === 'awaiting_ready' && captureId && !this.readyCaptures.has(captureId) && this.handlingCapture !== captureId) {
        this.handlingCapture = captureId;
        // Heartbeat/status polling continues while preparation is spoken.
        void this.prepareCapture(id, captureId, generation);
      } else if (this.connected && this.capturing && !this.handlingCapture) {
        await this.pauseInput(); if (this.current(generation, id)) this.update({ phase: 'recording' });
      } else if (!this.value.pendingCommandId && !this.handlingCapture) void this.resumeInput();
    } catch (e) {
      if (!this.current(generation, id)) return;
      if (sessionUnavailable(e)) { this.forgetUnavailableSession(); return; }
      await this.pauseInput();
      if (!this.current(generation, id)) return;
      this.update({ error: message(e), phase: 'idle' });
      if (e instanceof RelayError && [401, 403, 410].includes(e.status)) this.update({ conversation: false });
    } finally { if (this.pollOwner === owner) this.pollOwner = null; }
  }
  async startConversation() { if (this.disposed || this.ending) return; this.update({ conversation: true, error: null }); await this.resumeInput(); }
  private stopOutput() { this.outputEpoch++; this.outputBusy = false; this.outputAbort?.abort(); this.outputAbort = undefined; this.speech.stopSpeaking(); }
  async stopConversation() {
    const generation = this.generation;
    this.update({ conversation: false }); this.stopOutput();
    const stopped = this.pauseInput(); const epoch = this.inputEpoch; await stopped;
    if (this.current(generation) && epoch === this.inputEpoch) this.update({ phase: this.capturing ? 'recording' : 'idle' });
  }
  private async pauseInput() {
    this.recognizing = false; const epoch = ++this.inputEpoch; const generation = this.generation;
    await this.speech.stopListening();
    if (this.current(generation) && epoch === this.inputEpoch) this.update({ partial: '' });
  }
  private async resumeInput() {
    if (!this.value.conversation || !this.connected || this.capturing || this.value.pendingCommandId || this.recognizing || this.outputBusy || this.disposed) return;
    this.recognizing = true; const generation = this.generation; const id = this.value.sessionId!; const epoch = ++this.inputEpoch;
    const ownsInput = () => this.current(generation, id) && epoch === this.inputEpoch;
    const mayListen = () => ownsInput() && this.recognizing && this.value.conversation && this.connected && !this.capturing && !this.value.pendingCommandId && !this.outputBusy;
    this.update({ phase: 'connecting' });
    try {
      const { token } = await this.relay.token(id);
      if (!mayListen()) return;
      this.speechStarted = 0;
      await this.speech.listen(token, text => {
        if (!mayListen()) return;
        this.speechStarted = performance.now(); this.update({ partial: text });
      }, text => {
        if (!mayListen() || !text.trim()) return;
        this.update({ latency: { ...this.value.latency, recognitionMs: this.speechStarted ? performance.now() - this.speechStarted : undefined } });
        void this.submit('utterance', { text: text.trim() });
      }, error => {
        if (!ownsInput()) return;
        this.inputEpoch++; this.recognizing = false; this.update({ error, phase: 'idle', conversation: false });
      });
      if (!mayListen()) { if (ownsInput()) await this.pauseInput(); return; }
      this.update({ phase: 'listening' });
    } catch (e) {
      if (!ownsInput()) return;
      this.inputEpoch++; this.recognizing = false; this.update({ error: message(e), phase: 'idle', conversation: false });
    }
  }
  async submit(kind: CommandEnvelope['kind'], args: Record<string, unknown>) {
    const snapshot = this.value.snapshot;
    if (!snapshot?.projectSessionId || !this.connected || this.value.pendingCommandId || this.capturing || this.outputBusy) return;
    const generation = this.generation; const commandId = crypto.randomUUID();
    const command: CommandEnvelope = { version: 1, commandId, sessionId: snapshot.sessionId, projectSessionId: snapshot.projectSessionId,
      expectedProjectRevision: snapshot.projectRevision, kind, args, expiresAt: new Date(Date.now() + 120_000).toISOString() };
    // Lock and persist identity/expiry before any asynchronous work. Persist no transcript or audio.
    this.commandStarted = Date.now(); this.pendingExpiresAt = command.expiresAt;
    this.update({ pendingCommandId: commandId, phase: 'working', error: null });
    if (!this.remember()) { this.pendingExpiresAt = null; this.commandStarted = 0; this.update({ pendingCommandId: null, phase: 'idle' }); return; }
    if (kind === 'utterance') this.line('you', String(args.text));
    const ownsCommand = () => this.current(generation, snapshot.sessionId) && this.value.pendingCommandId === commandId;
    try {
      await this.pauseInput();
      if (!ownsCommand()) return;
      const response = await this.relay.submit(command);
      if (!ownsCommand()) return;
      if (response.result && !['queued', 'running'].includes(response.status)) await this.complete(response.result);
    } catch (e) {
      if (!ownsCommand()) return;
      if (e instanceof RelayError && [400, 401, 403, 409, 410, 429].includes(e.status)) {
        this.clearPending(); this.update({ phase: 'idle', error: message(e) });
      } else this.update({ error: 'Connection interrupted. Checking this request’s status without repeating it.' });
    }
  }
  action(type: string, args: Record<string, unknown> = {}) { return this.submit('session_action', { type, arguments: args }); }
  private async complete(result: CommandResult) {
    if (result.commandId !== this.value.pendingCommandId || this.disposed || this.ending) return;
    this.clearPending(); this.update({ error: null });
    const outcome = result.details?.nativeStatus ?? result.status;
    this.line('mixroom', result.message, outcome);
    if (this.value.conversation) {
      const generation = this.generation; const id = this.value.sessionId!;
      const speaking = this.say(result.message, generation, id); const epoch = this.outputEpoch;
      void speaking.catch(e => {
        if (this.current(generation, id) && epoch === this.outputEpoch && this.value.conversation) this.update({ error: `Result received. Audio response unavailable: ${message(e)}`, conversation: false });
      }).finally(() => {
        if (this.current(generation, id) && epoch === this.outputEpoch && !this.outputBusy) { this.update({ phase: this.capturing ? 'recording' : 'idle' }); void this.resumeInput(); }
      });
    } else this.update({ phase: 'idle' });
  }
  private async say(text: string, generation: number, id: string) {
    if (!this.current(generation, id)) return false;
    this.stopOutput(); const epoch = this.outputEpoch; this.outputBusy = true;
    const currentOutput = () => this.current(generation, id) && epoch === this.outputEpoch;
    try {
      await this.pauseInput(); if (!currentOutput()) return false;
      this.update({ phase: 'speaking' }); const controller = new AbortController(); this.outputAbort = controller;
      const start = performance.now();
      const audio = await this.relay.tts(id, text, controller.signal);
      if (!currentOutput()) { await audio.body?.cancel(); return false; }
      this.update({ latency: { ...this.value.latency, responseMs: performance.now() - start } });
      await this.speech.speak(audio);
      return currentOutput();
    } catch (e) { if (currentOutput()) throw e; return false; }
    finally { if (epoch === this.outputEpoch) { this.outputBusy = false; this.outputAbort = undefined; } }
  }
  private captureIsCurrent(id: string, captureId: string, generation: number) {
    return this.current(generation, id) && this.connected && !this.canceledCaptures.has(captureId) && this.value.snapshot?.state.captureId === captureId && this.value.snapshot.state.recordingPhase === 'awaiting_ready';
  }
  private async prepareCapture(id: string, captureId: string, generation: number) {
    try {
      await this.pauseInput(); if (!this.captureIsCurrent(id, captureId, generation)) return;
      const spoken = await this.say('Get ready. I will stop listening while you record. Your Mac will count down for two seconds.', generation, id);
      if (!spoken) { if (this.current(generation, id)) this.readyCaptures.add(captureId); return; }
      if (!this.captureIsCurrent(id, captureId, generation)) return;
      await this.pauseInput(); // Release even a late microphone permission grant before readiness.
      if (!this.captureIsCurrent(id, captureId, generation)) return;
      this.speech.stopSpeaking();
      await this.relay.ready(id, captureId);
      if (!this.current(generation, id)) return;
      this.readyCaptures.add(captureId); this.update({ phase: 'recording' });
    } catch (e) {
      if (!this.current(generation, id)) return;
      this.readyCaptures.add(captureId); this.update({ error: `Recording preparation failed: ${message(e)}` });
    } finally { if (this.current(generation, id) && this.handlingCapture === captureId) this.handlingCapture = null; }
  }
  async emergencyStop() {
    const id = this.value.sessionId, captureId = this.value.snapshot?.state.captureId, generation = this.generation;
    if (captureId) { this.canceledCaptures.add(captureId); this.readyCaptures.add(captureId); }
    this.stopOutput();
    // A pending browser permission dialog must never delay the native stop flag.
    const releaseInput = this.pauseInput();
    try { await Promise.all([releaseInput, id && captureId ? this.relay.emergencyStop(id, captureId) : Promise.resolve()]); }
    catch (e) { if (this.current(generation, id)) this.update({ error: `${message(e)} Stop recording on the Mac if it is offline.` }); }
  }
  async endSession() {
    if (this.ending || this.disposed) return;
    this.ending = true; const generation = ++this.generation; const id = this.value.sessionId;
    this.pollOwner = null; this.pairing = false; this.handlingCapture = null;
    this.update({ conversation: false, phase: 'idle' }); this.stopOutput();
    const releaseInput = this.pauseInput();
    try {
      await Promise.all([releaseInput, id ? this.relay.revoke(id) : Promise.resolve()]);
      if (!this.current(generation, id)) return;
      this.forgetSession(null);
    } catch (e) {
      if (!this.current(generation, id)) return;
      if (sessionUnavailable(e)) this.forgetUnavailableSession();
      else this.update({ error: `Could not revoke the session: ${message(e)}` });
    }
    finally { if (this.current(generation)) this.ending = false; }
  }
  /** React StrictMode may clean up and restart the same effect-owned instance. */
  activate() { if (!this.disposed) return; this.disposed = false; this.update({ conversation: false, phase: 'idle', partial: '' }); }
  deactivate() {
    this.generation++; this.inputEpoch++; this.recognizing = false; this.disposed = true;
    this.pollOwner = null; this.pairing = false; this.ending = false; this.handlingCapture = null;
    this.stopOutput(); void this.speech.stopListening().catch(() => {});
  }
  dispose() { this.deactivate(); this.listeners.clear(); }
}
function message(error: unknown) { return error instanceof Error ? error.message : 'The service is unavailable. Please try again.'; }
function sessionUnavailable(error: unknown) {
  return error instanceof RelayError && (
    (error.status === 404 && error.code === 'session_not_found') ||
    (error.status === 410 && ['session_expired_or_revoked', 'session_expired', 'session_revoked'].includes(error.code))
  );
}
