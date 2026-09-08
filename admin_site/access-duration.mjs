const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

export function durationExpiry(mode, count, date, now = new Date()) {
  if (mode === 'none') return '';
  let end;
  if (mode === 'date') end = new Date(date);
  else {
    const amount = Number(count);
    if (!Number.isSafeInteger(amount) || amount < 1) throw new Error('Enter a positive whole number of days or months.');
    end = new Date(now);
    if (mode === 'days') end.setTime(end.getTime() + amount * 86400000);
    else if (mode === 'months') {
      const day = end.getDate();
      end.setDate(1);
      end.setMonth(end.getMonth() + amount);
      const lastDay = new Date(end.getFullYear(), end.getMonth() + 1, 0).getDate();
      end.setDate(Math.min(day, lastDay));
    } else throw new Error('Choose an access period.');
  }
  if (!Number.isFinite(end.getTime()) || end <= now) throw new Error('Choose an end date and time in the future.');
  return end.toISOString();
}

export function localDateTime(iso) {
  if (!iso) return '';
  const date = new Date(iso);
  const part = value => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${part(date.getMonth() + 1)}-${part(date.getDate())}T${part(date.getHours())}:${part(date.getMinutes())}`;
}

export function durationFields({ noneLabel = 'No end date', allowNone = true, expiry = '', disabled = false, keepCurrent = false } = {}) {
  const mode = keepCurrent ? 'keep' : expiry ? 'date' : allowNone ? 'none' : 'days';
  return `<div data-duration data-current-expiry="${escape(expiry)}" class="form-stack">
    <div class="inspector-grid">
      <label class="search-input-wrap"><span class="search-label">Access period</span>
        <select data-duration-mode class="select-input" ${disabled ? 'disabled' : ''}>
          ${keepCurrent ? `<option value="keep" selected>Keep current period</option>` : ''}
          ${allowNone ? `<option value="none" ${mode === 'none' ? 'selected' : ''}>${escape(noneLabel)}</option>` : ''}
          <option value="days" ${mode === 'days' ? 'selected' : ''}>Days</option>
          <option value="months">Months</option>
          <option value="date" ${mode === 'date' ? 'selected' : ''}>End date</option>
        </select>
      </label>
      <label data-count-wrap class="search-input-wrap" ${['days', 'months'].includes(mode) ? '' : 'hidden'}><span class="search-label">Amount</span>
        <input data-duration-count class="text-input" type="number" min="1" step="1" value="1" ${disabled ? 'disabled' : ''} />
      </label>
      <label data-date-wrap class="search-input-wrap" ${mode === 'date' ? '' : 'hidden'}><span class="search-label">End date (local time)</span>
        <input data-duration-date class="text-input" type="datetime-local" value="${escape(localDateTime(expiry))}" ${disabled ? 'disabled' : ''} />
      </label>
    </div>
    <p data-duration-summary class="field-help">${expiry ? `Ends ${escape(new Date(expiry).toLocaleString())}.` : ''}</p>
  </div>`;
}

export function readDuration(root) {
  const control = root.querySelector('[data-duration]');
  if (!control) return '';
  const mode = control.querySelector('[data-duration-mode]').value;
  if (mode === 'keep') return control.dataset.currentExpiry || '';
  return durationExpiry(mode, control.querySelector('[data-duration-count]').value, control.querySelector('[data-duration-date]').value);
}

export function installDurationControls(document) {
  const update = event => {
    const control = event.target.closest('[data-duration]');
    if (!control) return;
    const mode = control.querySelector('[data-duration-mode]').value;
    control.querySelector('[data-count-wrap]').hidden = !['days', 'months'].includes(mode);
    control.querySelector('[data-date-wrap]').hidden = mode !== 'date';
    const summary = control.querySelector('[data-duration-summary]');
    try {
      const expiry = mode === 'keep' ? control.dataset.currentExpiry || '' : durationExpiry(mode, control.querySelector('[data-duration-count]').value, control.querySelector('[data-duration-date]').value);
      summary.textContent = expiry ? `Access ends ${new Date(expiry).toLocaleString()} (${Intl.DateTimeFormat().resolvedOptions().timeZone}).` : '';
    } catch (error) { summary.textContent = error.message; }
  };
  document.addEventListener('change', update);
  document.addEventListener('input', update);
}
