# Mixroom Education Website Invite Handoff

Status date: May 7, 2026

The public website needs to support Education invite links sent by the Mixroom
backend:

```text
https://www.mixroom.ai/signup?invite=<invite_token>
```

This page must use Mixroom account auth and the Mixroom App API. Do not create a
separate website-only account system.

## Production API

Use the current production App API base URL:

```text
https://guepfr96ah.execute-api.ap-northeast-2.amazonaws.com/prod
```

`https://api.mixroom.ai` is referenced in the API contract, but it did not
resolve from our environment on May 7, 2026. Use the execute-api URL until the
custom API domain is confirmed live.

## Required Flow

1. Read `invite` from the query string.
2. Ask the student to sign in or create a Mixroom account.
3. For existing accounts, call:

```http
POST /v1/auth/sign-in
Content-Type: application/json

{
  "identifier": "student@example.com",
  "password": "..."
}
```

4. For new email accounts, call:

```http
POST /v1/auth/sign-up
Content-Type: application/json

{
  "name": "Student Name",
  "email": "student@example.com",
  "password": "..."
}
```

Then ask for the emailed verification code and call:

```http
POST /v1/auth/confirm-sign-up
Content-Type: application/json

{
  "email": "student@example.com",
  "code": "123456"
}
```

5. Use the returned `tokens.idToken` or `tokens.accessToken` to accept the
Education invite:

```http
POST /v1/education/invites/<invite_token>/accept
Authorization: Bearer <token>
Content-Type: application/json

{}
```

6. Show success and tell the student to open Mixroom and sign in with the same
account. Optional app deep link:

```text
mixroom://education/invites/<invite_token>
```

## Browser Security Requirements

If the website uses a Content Security Policy, allow the App API in
`connect-src`:

```text
connect-src 'self' https://guepfr96ah.execute-api.ap-northeast-2.amazonaws.com https://api.mixroom.ai
```

Keep account tokens in memory only for the accept request. Do not put auth
tokens in URLs, logs, analytics events, localStorage, or sessionStorage.

## Acceptance Tests

- `/signup?invite=<token>` renders an Education-specific accept page.
- Existing student can sign in and accept the invite.
- New student can create an account, verify email, and accept the invite.
- Invalid/missing token shows a clear error.
- Already accepted/revoked/expired invite shows the backend error.
- Seat count updates in the teacher Education UI after acceptance.
- The page does not create newsletter/waitlist-only accounts.
- Browser console has no CSP or CORS errors.
