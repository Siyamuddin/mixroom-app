# Auth And Account Flows

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-06-04  
Update trigger: Update this when sign-in, sign-up, token storage, account
deletion, social auth, subscription identity, or employee/admin auth behavior
changes.

## Purpose

This page explains how Mixroom identifies users, stores auth state, connects
account UI to backend APIs, and separates app-user auth from employee/admin
auth.

## Client Entry Points

- `lib/screens/auth_gate.dart`
- `lib/screens/login.dart`
- `lib/screens/account.dart`
- `lib/helpers/auth_service.dart`
- `lib/helpers/app_user_service.dart`
- `lib/helpers/native_social_sign_in.dart`
- `lib/core/security/sensitive_storage.dart`
- `lib/widgets/delete_account_sheet.dart`

## Backend Entry Points

- `backend/app_api/src/handlers/api_auth.py`
- `backend/app_api/src/handlers/api_users.py`
- `backend/app_api/src/common/auth.py`
- `backend/app_api/src/common/app_auth_tokens.py`
- `backend/app_api/src/common/password_auth.py`
- `backend/app_api/src/common/social_auth.py`
- `backend/app_api/src/common/native_auth.py`
- `backend/app_api/src/common/users.py`

## Main Flows

### App Sign-In

The app collects email/password or native social-provider credentials. The app
API validates credentials and returns Mixroom app auth state. The client stores
sensitive auth material through `SensitiveStorage`, not plain shared
preferences.

### Auth Gate

`AuthGate` decides whether the user sees login, onboarding/account recovery, or
the signed-in app shell. Changes here can affect every app launch and upgrade
path.

### Account Profile

Account UI reads current user state from `AuthService` and related user helpers.
Backend user records live behind app API user endpoints.

### Delete Account

Deletion starts in `delete_account_sheet.dart`. Social accounts may require
provider re-auth before destructive account removal. Billing cancellation still
belongs to App Store or Google Play where those subscriptions were purchased.

### Employee/Admin Auth

Employee-facing admin auth is separate from normal app user auth. Cognito is
still referenced for admin and compatibility paths. Do not assume app-user auth
and employee auth share the same authorization model.

## Security Rules

- Do not log credentials, tokens, provider identity tokens, refresh tokens, or
  password reset payloads.
- Keep auth tokens in OS-protected storage.
- Treat account deletion as a high-risk flow and test it with email/password and
  each enabled social provider.
- Update legal/privacy docs if the collected identity data changes.

## Tests To Check

- `backend/app_api/tests/test_api_auth.py`
- `backend/app_api/tests/test_auth_runtime.py`
- `backend/app_api/tests/test_password_auth.py`
- `backend/app_api/tests/test_native_auth.py`
- `backend/app_api/tests/test_api_users.py`

