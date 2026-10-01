import { lazy, Suspense, useCallback, useEffect, useRef, useState, type FormEvent } from 'react';
import { AUTH_STORAGE, LocalAuth, relayAddress, type LocalSession } from './auth/local';
import './voice/studio.css';
import './auth.css';

type ConnectedStudio = { relay: string; session: LocalSession };
const VoiceStudio = lazy(() => import('./voice/VoiceStudio').then(module => ({ default: module.VoiceStudio })));
const defaultAddress = import.meta.env.VITE_VOICE_RELAY_URL || (['localhost', '127.0.0.1', '[::1]'].includes(window.location.hostname) ? 'http://127.0.0.1:8765/api/voice' : '');
function remembered(): ConnectedStudio | null {
  try {
    const value = JSON.parse(sessionStorage.getItem(AUTH_STORAGE) || 'null');
    return value?.session?.access_token && Date.parse(value.session.expiresAt) > Date.now() ? { relay: relayAddress(value.relay), session: value.session } : null;
  } catch { return null; }
}
export default function App() {
  const [saved] = useState(remembered);
  const [studio, setStudio] = useState<ConnectedStudio | null>(null);
  const [loading, setLoading] = useState(!!saved);
  const [error, setError] = useState('');
  const token = useRef('');
  const accessToken = useCallback(async () => token.current, []);
  useEffect(() => {
    if (!saved) return;
    let active = true;
    void new LocalAuth(saved.relay).status(saved.session.access_token).then(() => {
      if (active) { token.current = saved.session.access_token; setStudio(saved); }
    }).catch(() => { if (active) { sessionStorage.removeItem(AUTH_STORAGE); setError('Your studio session ended. Sign in again.'); } }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [saved]);
  const connected = (next: ConnectedStudio) => {
    token.current = next.session.access_token;
    sessionStorage.setItem(AUTH_STORAGE, JSON.stringify(next));
    setStudio(next); setError('');
  };
  const signOut = () => {
    const previous = studio;
    token.current = ''; sessionStorage.removeItem(AUTH_STORAGE); setStudio(null);
    if (previous) void new LocalAuth(previous.relay).logout(previous.session.access_token).catch(() => { setError('Signed out here. The server session will expire automatically.'); });
  };
  if (studio) return <Suspense fallback={<main className="mixroom-studio mr-auth-shell"><p role="status">Opening your studio…</p></main>}><VoiceStudio key={studio.session.access_token} userId={studio.session.user.id} accessToken={accessToken} relayUrl={studio.relay} onSignOut={signOut} /></Suspense>;
  return <div className="mixroom-studio mr-auth-shell"><header className="mr-header"><a className="mr-brand" href="/"><span aria-hidden="true">Ⅲ</span> MixRoom</a><span className="mr-eyebrow">VOICE STUDIO</span></header><main className="mr-auth-main"><section><p className="mr-eyebrow">KEEP THE IDEA MOVING.</p><h1>The control room,<br /><em>within reach.</em></h1><p>Record a take. Shape the mix. Remember the idea.<br />Your voice runs the session. Your Mac makes the music.</p><div className="mr-auth-lines" aria-hidden="true"><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /></div></section><section className="mr-auth-form">{loading ? <p role="status">Opening your studio…</p> : <SignIn initialError={error} onConnected={connected} />}</section></main><footer className="mr-auth-footer">Made for musicians who have their hands full.</footer></div>;
}
function SignIn({ initialError, onConnected }: { initialError: string; onConnected: (studio: ConnectedStudio) => void }) {
  const [busy, setBusy] = useState(false), [error, setError] = useState(initialError);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy) return;
    const form = new FormData(event.currentTarget); setBusy(true); setError('');
    try {
      const relay = relayAddress(String(form.get('address') ?? ''));
      const session = await new LocalAuth(relay).login(String(form.get('password') ?? ''));
      onConnected({ relay, session });
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not open your studio.'); } finally { setBusy(false); }
  }
  return <><p className="mr-eyebrow">YOUR SPACE TO CREATE</p><h2>Open your studio.</h2><p>Connect to the studio running on your Mac.</p><form onSubmit={event => void submit(event)}><label htmlFor="mr-address">Studio address</label><input id="mr-address" name="address" type="url" autoComplete="url" defaultValue={defaultAddress} placeholder="https://your-studio.example/api/voice" required disabled={busy} spellCheck={false} /><label htmlFor="mr-password">Studio password</label><input id="mr-password" name="password" type="password" autoComplete="current-password" required disabled={busy} />{error && <p role="alert" className="mr-auth-error">{error}</p>}<button type="submit" className="mr-primary" disabled={busy}>{busy ? 'Opening studio…' : 'Open studio'} <span aria-hidden="true">↗</span></button></form><p className="mr-hint">Use your Mac’s local address on this laptop, or its secure studio link from your phone.</p></>;
}
