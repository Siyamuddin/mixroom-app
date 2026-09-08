"""Expiry rules shared by admin grants, class access, and student memberships."""
from datetime import datetime, timezone


def parse_access_expiry(value):
    if not value:
        return None
    try:
        result = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        if result.tzinfo is None:
            raise ValueError('Timezone required')
        return result.astimezone(timezone.utc)
    except (ValueError, TypeError) as exc:
        raise ValueError('Access end date must include a valid date, time, and timezone.') from exc


def access_period_active(record, *, now=None):
    try:
        expiry = parse_access_expiry(record.get('access_expires_at'))
    except ValueError:
        return False
    return expiry is None or expiry > (now or datetime.now(timezone.utc))


def normalize_access_expiry(value, *, now=None):
    expiry = parse_access_expiry(value)
    if expiry is None:
        return ''
    if expiry <= (now or datetime.now(timezone.utc)):
        raise ValueError('Access end date must be in the future.')
    return expiry.isoformat()


def saved_access_expiry(payload, current):
    if 'access_expires_at' not in payload:
        return current.get('access_expires_at', '')
    value = payload.get('access_expires_at') or ''
    # Editing other fields on an expired record must remain possible.
    if value == current.get('access_expires_at', ''):
        return value
    return normalize_access_expiry(value)


def earliest_access_expiry(*records):
    dates = [parse_access_expiry(record.get('access_expires_at')) for record in records]
    dates = [date for date in dates if date is not None]
    return min(dates).isoformat() if dates else ''
