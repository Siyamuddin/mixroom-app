import test from 'node:test';
import assert from 'node:assert/strict';
import { parseRoster, setupEducationInvites } from '../education-invites.mjs';

function fixture(request) {
  const nodes = new Map();
  const root = { querySelector(selector) {
    if (!nodes.has(selector)) nodes.set(selector, { value: '', listeners: {}, querySelector() { return null; }, querySelectorAll() { return []; }, addEventListener(name, callback) { this.listeners[name] = callback; } });
    return nodes.get(selector);
  } };
  globalThis.window = { addEventListener() {} };
  const school = { organization_id: 'school', plan_code: 'education', name: 'School' };
  const controller = setupEducationInvites({ root, getOrganization: () => school, canEdit: () => true,
    request: (_, options) => request(JSON.parse(options.body)), onOrganization() {} });
  controller.render();
  return { node: selector => root.querySelector(selector), school, controller };
}

test('accepts a pasted spreadsheet column and common separators', () => {
  assert.deepEqual(parseRoster('a@example.com\r\nb@example.com, c@example.com;\td@example.com'),
    ['a@example.com', 'b@example.com', 'c@example.com', 'd@example.com']);
});

test('review sends nothing and disables send when there are insufficient seats', async () => {
  const calls = [];
  const f = fixture(async body => { calls.push(body); return { rows: [{ email: 'a@example.com', status: 'ready' }], seats_needed: 1, seats_available: 0, duplicates: 0, can_send: false }; });
  f.node('[data-roster]').value = 'a@example.com';
  await f.node('[data-preview]').listeners.click();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].action, 'preview');
  assert.equal(f.node('[data-send]').disabled, true);
  assert.match(f.node('[data-notice]').textContent, /Not enough seats/);
});

test('bulk send skips existing students and retries a failed email using the same invite', async () => {
  const calls = [];
  const f = fixture(async body => {
    calls.push(body);
    if (body.action === 'preview') return { rows: [
      { email: 'new@example.com', status: 'ready' },
      { email: 'active@example.com', status: 'already_active' },
      { email: 'pending@example.com', status: 'pending', invite_url: 'link' },
    ], seats_needed: 1, seats_available: 5, duplicates: 0, can_send: true };
    return { email: body.email, status: body.resend ? 'sent' : 'email_failed', invite_url: 'same-link' };
  });
  f.node('[data-roster]').value = 'new@example.com active@example.com pending@example.com';
  await f.node('[data-preview]').listeners.click();
  await f.node('[data-send]').listeners.click();
  assert.deepEqual(calls.filter(call => call.action === 'send').map(call => call.email), ['new@example.com']);
  assert.equal(f.node('[data-retry]').hidden, false);
  await f.node('[data-retry]').listeners.click();
  const sends = calls.filter(call => call.action === 'send');
  assert.equal(sends[1].resend, true);
  assert.equal(f.node('[data-retry]').hidden, true);
});

test('switching schools clears the old reviewed roster', async () => {
  const f = fixture(async () => ({ rows: [{ email: 'a@example.com', status: 'ready' }], can_send: true, seats_needed: 1, seats_available: 5 }));
  f.node('[data-roster]').value = 'a@example.com';
  await f.node('[data-preview]').listeners.click();
  f.school.organization_id = 'another-school';
  f.controller.render();
  assert.equal(f.node('[data-roster]').value, '');
  assert.equal(f.node('[data-send]').disabled, true);
});

test('shared code and link generate without emails, copy separately, and revoke together', async (t) => {
  const copied = [];
  const previousNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { clipboard: { writeText: async value => copied.push(value) } } });
  t.after(() => {
    if (previousNavigator) Object.defineProperty(globalThis, 'navigator', previousNavigator);
    else delete globalThis.navigator;
  });
  const { setupEducationClassLink } = await import('../education-invites.mjs');
  const nodes = new Map();
  const root = { querySelector(selector) {
    if (!nodes.has(selector)) nodes.set(selector, { value: '', listeners: {}, addEventListener(name, callback) { this.listeners[name] = callback; } });
    return nodes.get(selector);
  } };
  const calls = [];
  const controller = setupEducationClassLink({ root,
    getOrganization: () => ({ organization_id: 'school', plan_code: 'education' }), canEdit: () => true,
    request: async (_, options) => {
      const body = JSON.parse(options.body); calls.push(body);
      return { class_invite: body.action === 'class_link_create' ? { invite_url: 'class-link', invite_token: 'edu.school.sharedtoken', invite_code: 'ABCDE-23456' } : {} };
    },
  });
  controller.render();
  await new Promise(resolve => setTimeout(resolve, 0));
  await root.querySelector('[data-create]').listeners.click();
  assert.equal(root.querySelector('[data-link]').value, 'class-link');
  assert.equal(root.querySelector('[data-copy-link]').hidden, false);
  assert.equal(root.querySelector('[data-code]').value, 'ABCDE-23456');
  assert.equal(root.querySelector('[data-copy-code]').hidden, false);
  await root.querySelector('[data-copy-code]').listeners.click();
  await root.querySelector('[data-copy-link]').listeners.click();
  assert.deepEqual(copied, ['ABCDE-23456', 'class-link']);
  await root.querySelector('[data-revoke]').listeners.click();
  assert.equal(root.querySelector('[data-code]').value, '');
  assert.equal(root.querySelector('[data-code]').hidden, true);
  assert.equal(root.querySelector('[data-copy-code]').hidden, true);
  assert.equal(root.querySelector('[data-link]').hidden, true);
  assert.deepEqual(calls.map(call => call.action), ['class_link_get', 'class_link_create', 'class_link_revoke']);
  assert.ok(calls.every(call => !('emails' in call) && !('email' in call)));
});

test('dashboard enables education codes for employee admins without developer permissions', async () => {
  const { readFileSync } = await import('node:fs');
  const { runInNewContext } = await import('node:vm');
  const source = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
  const render = source.slice(source.indexOf('function renderEducationInvites()'), source.indexOf('function renderBillingEducationSummary()'));
  let controls;
  const context = {
    educationClassLinkController: undefined, educationInvitesController: undefined,
    document: { querySelector() { return {}; } },
    getSelectedBillingOrganization() {}, fetchAdminJson() {},
    setupEducationClassLink(options) { controls = options; return { render() {} }; },
    setupEducationInvites() { return { render() {} }; },
    tokens: { idToken: 'employee-session' }, state: { collaborationConfigurable: true },
    canEditBillingControlPlane: () => false,
  };
  runInNewContext(render + '\nrenderEducationInvites();', context);
  assert.equal(controls.canEdit(), true);
  context.tokens = null;
  assert.equal(controls.canEdit(), false);
  context.tokens = { idToken: 'employee-session' };
  context.state.collaborationConfigurable = false;
  assert.equal(controls.canEdit(), false);
});

test('employee admins can provision classes and edit billing records without AI-editor access', async () => {
  const { readFileSync } = await import('node:fs');
  const { runInNewContext } = await import('node:vm');
  const source = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
  const helpers = source.slice(source.indexOf('function canEditBillingCatalog()'), source.indexOf('function canGrantAiPrompts()'));
  const context = {
    tokens: { idToken: 'employee-session' },
    state: { collaborationConfigurable: true, billingCatalogConfigurable: true },
    canViewAiRuntimeSettings: () => false,
  };
  runInNewContext(helpers, context);
  assert.equal(context.canEditBillingControlPlane(), true);
  assert.equal(context.canEditBillingCatalog(), true);
  context.tokens = null;
  assert.equal(context.canEditBillingControlPlane(), false);
  assert.equal(context.canEditBillingCatalog(), false);
  context.tokens = { idToken: 'employee-session' };
  context.state.collaborationConfigurable = false;
  context.state.billingCatalogConfigurable = false;
  assert.equal(context.canEditBillingControlPlane(), false);
  assert.equal(context.canEditBillingCatalog(), false);
});
