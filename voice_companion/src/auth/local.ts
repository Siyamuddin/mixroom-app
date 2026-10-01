export type LocalSession = { access_token: string; expiresAt: string; user: { id: string } };
export const AUTH_STORAGE = 'mixroom.local-auth.v1';
export function relayAddress(value: string): string {
  const url = new URL(value.trim());
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && loopback)) || url.username || url.password || url.search || url.hash) {
    throw new Error('Use an HTTPS studio address, or HTTP on this Mac’s localhost.');
  }
  url.pathname = url.pathname.replace(/\/+$/, '') || '/api/voice';
  if (url.pathname !== '/api/voice') throw new Error('The studio address must end with /api/voice.');
  return url.href.replace(/\/$/, '');
}
export class LocalAuth {
  readonly base: string;
  readonly fetcher: typeof fetch;
  constructor(relay: string, fetcher: typeof fetch = (...args) => globalThis.fetch(...args)) { this.base = relayAddress(relay).replace(/\/api\/voice$/, '/api/auth'); this.fetcher = fetcher; }
  async request(path: string, token?: string, password?: string): Promise<LocalSession> {
    const response = await this.fetcher(this.base + path, {
      method: path === '/status' ? 'GET' : 'POST',
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(password !== undefined ? { 'Content-Type': 'application/json' } : {}) },
      body: password === undefined ? undefined : JSON.stringify({ password }),
      signal: AbortSignal.timeout(12_000), redirect: 'error',
    });
    if (!response.ok) {
      let message = 'Could not open your studio. Check the address and password.';
      try { const body = await response.json(); if (typeof body.error?.message === 'string') message = body.error.message; } catch { /* Do not expose gateway HTML. */ }
      throw new Error(message);
    }
    return response.json();
  }
  login(password: string) { return this.request('/login', undefined, password); }
  status(token: string) { return this.request('/status', token); }
  logout(token: string) { return this.request('/logout', token); }
}
