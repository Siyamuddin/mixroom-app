import test from 'node:test';
import assert from 'node:assert/strict';
import { LocalAuth, relayAddress } from '../src/auth/local.ts';

test('local relay URLs allow exact loopback and HTTPS without credentials', () => {
  assert.equal(relayAddress('http://127.0.0.1:8765'), 'http://127.0.0.1:8765/api/voice');
  assert.equal(relayAddress('http://[::1]:8765/api/voice/'), 'http://[::1]:8765/api/voice');
  assert.equal(relayAddress('https://studio.example'), 'https://studio.example/api/voice');
  for (const bad of ['http://192.168.1.2:8765', 'http://localhost.attacker.test', 'https://user:pass@studio.example', 'https://studio.example?token=secret', 'https://studio.example/#secret', 'file:///api/voice']) assert.throws(() => relayAddress(bad));
});
test('login sends only password to selected API and disallows redirects', async () => {
  let request: RequestInit | undefined;
  const auth = new LocalAuth('https://studio.example/api/voice', async (url, init) => {
    assert.equal(url, 'https://studio.example/api/auth/login'); request = init;
    return Response.json({ access_token: 'fake-session-token', expiresAt: '2027-01-01', user: { id: 'owner' } });
  });
  const result = await auth.login('test-only-password');
  assert.equal(result.user.id, 'owner');
  assert.equal(request?.redirect, 'error');
  assert.deepEqual(JSON.parse(request?.body as string), { password: 'test-only-password' });
});
test('session check uses bearer header without sending the studio password', async () => {
  const auth = new LocalAuth('http://localhost:8765', async (url, init) => {
    assert.equal(url, 'http://localhost:8765/api/auth/status');
    assert.equal(init?.method, 'GET'); assert.equal(init?.body, undefined);
    assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer fake-token');
    return Response.json({ user: { id: 'owner' } });
  });
  await auth.status('fake-token');
});
test('upstream HTML and failures never become successful local sessions', async () => {
  const auth = new LocalAuth('https://studio.example', async () => new Response('<html>private gateway details</html>', { status: 502 }));
  await assert.rejects(auth.login('test-only-password'), /Could not open your studio/);
});
