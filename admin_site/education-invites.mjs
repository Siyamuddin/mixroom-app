import { durationFields, readDuration } from "./access-duration.mjs";

export function parseRoster(text) {
  return text.split(/[\s,;]+/).map(value => value.trim()).filter(Boolean);
}

const labels = {
  ready: 'Ready', invalid: 'Invalid email',
  already_active: 'Already active', existing_staff: 'Teacher / staff',
  pending: 'Invite pending', sent: 'Email sent',
  email_failed: 'Email failed: seat reserved', sending: 'Sending…',
  error: 'Request failed',
};

export function setupEducationInvites({ root, getOrganization, request, canEdit, onOrganization }) {
  let organizationId = '', review = null, rows = [], busy = false, message = '', accessExpiry = '';
  const durationRoot = root.querySelector('[data-invite-duration]');
  durationRoot.innerHTML = durationFields({ noneLabel: 'Same as class' });
  const input = root.querySelector('[data-roster]');
  const language = root.querySelector('[data-language]');
  const preview = root.querySelector('[data-preview]');
  const send = root.querySelector('[data-send]');
  const retry = root.querySelector('[data-retry]');
  const results = root.querySelector('[data-results]');
  const notice = root.querySelector('[data-notice]');
  const title = root.querySelector('[data-organization]');
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const api = body => request('/v1/internal/admin/billing/education-invites', { method: 'POST', body: JSON.stringify(body) });

  function render() {
    const organization = getOrganization();
    // Keep a running batch bound to its reviewed school even if another row is selected.
    if (!busy && organizationId !== (organization?.organization_id || '')) {
      organizationId = organization?.organization_id || '';
      review = null; rows = []; message = ''; input.value = ''; accessExpiry = '';
      durationRoot.innerHTML = durationFields({ noneLabel: 'Same as class' });
    }
    root.hidden = !busy && organization?.plan_code !== 'education';
    if (!busy) title.textContent = organization?.name || 'Selected school';
    durationRoot.querySelectorAll('input, select').forEach(control => { control.disabled = busy || !canEdit(); });
    input.disabled = busy || !canEdit();
    language.disabled = busy || !canEdit();
    preview.disabled = busy || !canEdit() || !input.value.trim();
    send.disabled = busy || !canEdit() || !review?.can_send || !rows.some(row => row.status === 'ready');
    send.hidden = !review && !busy;
    send.textContent = `Send ${rows.filter(row => row.status === 'ready').length} invites`;
    retry.hidden = !rows.some(row => ['email_failed', 'error'].includes(row.status));
    retry.disabled = busy || !canEdit();
    notice.textContent = message;
    results.innerHTML = rows.length ? `<table class="billing-table"><thead><tr><th>Student email</th><th>Result</th><th>Action</th></tr></thead><tbody>${rows.map((row, index) => `<tr><td>${escape(row.email)}</td><td>${escape(labels[row.status] || row.status)}${row.access_expires_at ? `<div class="panel-meta">Access ends ${escape(new Date(row.access_expires_at).toLocaleString())}</div>` : ''}${row.message ? `<div class="panel-meta">${escape(row.message)}</div>` : ''}</td><td>${row.invite_url ? `<button type="button" class="button button-ghost" data-copy="${index}">Copy link</button>` : ''}${['pending', 'email_failed'].includes(row.status) ? `<button type="button" class="button button-ghost" data-resend="${index}" ${busy || !canEdit() ? 'disabled' : ''}>Resend email</button>` : ''}</td></tr>`).join('')}</tbody></table>` : '';
  }

  durationRoot.addEventListener('change', () => { review = null; rows = []; message = 'Period changed. Review emails again.'; render(); });
  input.addEventListener('input', () => { review = null; rows = []; message = ''; render(); });
  preview.addEventListener('click', async () => {
    if (busy || !canEdit()) return;
    const emails = parseRoster(input.value);
    if (!emails.length || emails.length > 500) {
      message = 'Paste 1–500 emails per batch. Split larger classes into multiple batches.'; render(); return;
    }
    try { accessExpiry = readDuration(durationRoot); }
    catch (error) { message = error.message; render(); return; }
    busy = true; message = 'Checking emails and available seats…'; render();
    try {
      review = await api({ action: 'preview', organization_id: organizationId, emails, access_expires_at: accessExpiry });
      rows = review.rows;
      onOrganization(review.organization);
      const invalid = rows.filter(row => row.status === 'invalid').length;
      message = `${review.seats_needed} new invites · ${review.seats_available} seats available${review.duplicates ? ` · ${review.duplicates} duplicates removed` : ''}. `;
      if (invalid) message += `Correct ${invalid} invalid email(s) and review again. `;
      if (review.seats_needed > review.seats_available) message += 'Not enough seats. Increase the school’s seat limit or reduce this roster, then review again. ';
      if (!invalid && review.seats_needed <= review.seats_available) message += 'Existing students and invites are skipped.';
    } catch (error) { review = null; rows = []; message = error.message || 'Could not review the roster.'; }
    finally { busy = false; render(); }
  });

  async function runBatch(indices, resend = false) {
    if (busy || !canEdit()) return;
    const batchOrg = organizationId;
    const locale = language.value;
    busy = true;
    for (let position = 0; position < indices.length; position += 1) {
      const index = indices[position];
      const previous = rows[index];
      rows[index] = { ...previous, status: 'sending', message: '' };
      message = `Processing ${position + 1} of ${indices.length}. Keep this page open.`;
      render();
      try {
        const result = await api({ action: 'send', organization_id: batchOrg, email: previous.email, locale,
          access_expires_at: accessExpiry, resend: resend || previous.status === 'email_failed' });
        rows[index] = { ...previous, ...result, message: result.email_error === 'suppressed'
          ? 'Email provider blocked this address. Copy the link or confirm a different email with the student.' : '' };
      } catch (error) {
        rows[index] = { ...previous, status: 'error', message: error.message || 'Request failed. Retry checks for an existing invitation first.' };
      }
    }
    busy = false;
    review = null;
    message = `${rows.filter(row => row.status === 'sent').length} emails sent. ${rows.filter(row => ['email_failed', 'error'].includes(row.status)).length} need attention.`;
    render();
    // Refresh capacity without reserving seats or sending mail.
    try {
      const refreshed = await api({ action: 'preview', organization_id: batchOrg, emails: [rows[0]?.email] });
      onOrganization(refreshed.organization);
    } catch { /* Per-student outcomes remain available if refreshing fails. */ }
  }

  send.addEventListener('click', () => {
    if (review?.can_send) return runBatch(rows.flatMap((row, index) => row.status === 'ready' ? [index] : []));
  });
  retry.addEventListener('click', () => runBatch(rows.flatMap((row, index) => ['email_failed', 'error'].includes(row.status) ? [index] : [])));
  results.addEventListener('click', async event => {
    const copy = event.target.closest('[data-copy]');
    if (copy) {
      try { await navigator.clipboard.writeText(rows[Number(copy.dataset.copy)].invite_url); message = 'Invite link copied. Share it only with that student.'; }
      catch { message = `Copy this student’s link: ${rows[Number(copy.dataset.copy)].invite_url}`; }
      render();
    }
    const resend = event.target.closest('[data-resend]');
    if (resend) await runBatch([Number(resend.dataset.resend)], true);
  });
  window.addEventListener('beforeunload', event => { if (busy) { event.preventDefault(); event.returnValue = ''; } });
  return { render };
}

export function setupEducationClassLink({ root, getOrganization, request, canEdit }) {
  let organizationId = '', link = '', code = '', busy = false, message = '';
  const create = root.querySelector('[data-create]');
  const copy = root.querySelector('[data-copy-link]');
  const copyCode = root.querySelector('[data-copy-code]');
  const codeField = root.querySelector('[data-code]');
  const revoke = root.querySelector('[data-revoke]');
  const field = root.querySelector('[data-link]');
  const notice = root.querySelector('[data-notice]');
  function paint() {
    create.hidden = Boolean(link);
    create.disabled = busy || !canEdit();
    copy.hidden = revoke.hidden = field.hidden = !link;
    copy.disabled = revoke.disabled = busy || !canEdit();
    copyCode.hidden = codeField.hidden = !code;
    copyCode.disabled = busy || !canEdit();
    codeField.value = code;
    field.value = link;
    notice.textContent = message;
  }
  async function action(actionName) {
    const target = organizationId;
    busy = true; message = ''; paint();
    try {
      const result = await request('/v1/internal/admin/billing/education-invites', {
        method: 'POST', body: JSON.stringify({ action: `class_link_${actionName}`, organization_id: target }),
      });
      if (target !== organizationId) return;
      link = result.class_invite?.invite_url || '';
      code = result.class_invite?.invite_code || result.class_invite?.invite_token || '';
      message = actionName === 'revoke' ? 'Code and link revoked. Current students keep their access.' : '';
    } catch (error) { if (target === organizationId) message = error.message || 'Could not update the education invite.'; }
    finally { if (target === organizationId) { busy = false; paint(); } }
  }
  create.addEventListener('click', () => { if (!busy && canEdit()) return action('create'); });
  revoke.addEventListener('click', () => { if (!busy && canEdit()) return action('revoke'); });
  copyCode.addEventListener('click', async () => {
    if (!code) return;
    try { await navigator.clipboard.writeText(code); message = 'Education invite code copied.'; }
    catch { message = 'Select and copy the code above.'; }
    paint();
  });
  copy.addEventListener('click', async () => {
    if (!link) return;
    try { await navigator.clipboard.writeText(link); message = 'Class link copied.'; }
    catch { message = 'Select and copy the link above.'; }
    paint();
  });
  return { render() {
    const org = getOrganization();
    const next = org?.plan_code === 'education' ? org.organization_id : '';
    root.hidden = !next;
    if (next !== organizationId) {
      organizationId = next; link = ''; code = ''; message = ''; busy = false;
      if (next && canEdit()) void action('get');
    }
    paint();
  } };
}
