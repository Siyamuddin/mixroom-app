export type NativeState = {
  projectName?: string; projectReady?: boolean; busy?: boolean; inputReady?: boolean;
  tracks?: { id: number; name: string; type: string; volumeDb?: number; muted?: boolean; solo?: boolean }[];
  selectedTrackIds?: number[];
  transport?: { playing?: boolean; recording?: boolean; positionSeconds?: number; tempo?: number; timeSignature?: string };
  recordingPhase?: string; captureId?: string; captureRemainingSeconds?: number;
  comparison?: { available: boolean; id?: string; side?: string };
  notes?: { id: string; text: string; completed: boolean; playheadMs: number; trackId?: number }[];
};
export type SessionSnapshot = {
  sessionId: string; status: string; projectSessionId: string | null; projectRevision: number;
  nativeConnected: boolean; state: NativeState; updatedAt: string;
};
export type CommandEnvelope = {
  version: 1; commandId: string; sessionId: string; projectSessionId: string;
  expectedProjectRevision: number; kind: 'utterance' | 'session_action';
  args: Record<string, unknown>; expiresAt: string;
};
export type CommandResult = {
  commandId: string; status: string; message: string; state?: NativeState;
  details?: { nativeStatus?: string; [key: string]: unknown };
};
export type CommandStatus = { commandId: string; status: string; result?: CommandResult | null };
export class RelayError extends Error {
  readonly status: number;
  readonly code: string;
  readonly serverDate?: number;
  constructor(message: string, status: number, code: string, serverDate?: number) {
    super(message); this.status = status; this.code = code;
    this.serverDate = Number.isFinite(serverDate) ? serverDate : undefined;
  }
}

export class VoiceRelay {
  readonly baseUrl: string;
  readonly accessToken: () => Promise<string>;
  readonly fetcher: typeof fetch;
  constructor(baseUrl: string, accessToken: () => Promise<string>, fetcher: typeof fetch = (...args) => globalThis.fetch(...args)) {
    const url = new URL(baseUrl);
    if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) throw new Error('Use an HTTPS voice relay.');
    if (url.username || url.password || url.search || url.hash) throw new Error('Relay URLs cannot contain credentials.');
    this.baseUrl = baseUrl.replace(/\/$/, ''); this.accessToken = accessToken; this.fetcher = fetcher;
  }
  async response(path: string, method = 'GET', body?: unknown, signal?: AbortSignal): Promise<Response> {
    const token = await this.accessToken();
    if (!token) throw new RelayError('Sign in to connect your studio.', 401, 'sign_in_required');
    const response = await this.fetcher(this.baseUrl + path, {
      method, headers: { Authorization: `Bearer ${token}`, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      body: body === undefined ? undefined : JSON.stringify(body), signal: signal ?? AbortSignal.timeout(12_000),
    });
    if (!response.ok) {
      let error: { message?: string; code?: string } = {};
      try { error = (await response.json()).error ?? {}; } catch { /* Never expose upstream HTML. */ }
      const date = response.headers.get('Date');
      throw new RelayError(error.message ?? 'The voice service could not complete this request.', response.status, error.code ?? 'service_error', date ? Date.parse(date) : undefined);
    }
    return response;
  }
  async json<T>(path: string, method = 'GET', body?: unknown): Promise<T> { return (await this.response(path, method, body)).json(); }
  createPairing() { return this.json<{ sessionId: string; pairingCode: string; expiresAt: string }>('/pairing', 'POST', {}); }
  state(id: string) { return this.json<SessionSnapshot>(`/sessions/${encodeURIComponent(id)}/state`); }
  presence(id: string) { return this.json(`/sessions/${encodeURIComponent(id)}/presence`, 'POST', {}); }
  submit(command: CommandEnvelope) { return this.json<CommandStatus>(`/sessions/${command.sessionId}/commands`, 'POST', command); }
  status(id: string, command: string) { return this.json<CommandStatus>(`/sessions/${id}/commands/${command}`); }
  ready(id: string, captureId: string) { return this.json(`/sessions/${id}/capture-ready`, 'POST', { captureId }); }
  emergencyStop(id: string, captureId: string) { return this.json(`/sessions/${id}/emergency-stop`, 'POST', { captureId }); }
  revoke(id: string) { return this.json(`/sessions/${id}`, 'DELETE'); }
  token(sessionId: string) { return this.json<{ token: string }>('/speech/token', 'POST', { sessionId }); }
  tts(sessionId: string, text: string, signal?: AbortSignal) { return this.response('/speech/tts', 'POST', { sessionId, text }, signal); }
}
