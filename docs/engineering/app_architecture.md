# App Architecture

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-08-29
Update trigger: Update this when navigation, state ownership, service
boundaries, backend contracts, or top-level product surfaces change.

## Shape Of The App

Mixroom is a Flutter app with native audio processing. The Flutter layer owns
screens, user workflows, app state, persistence orchestration, cloud calls, and
most product logic. The native engine owns low-latency audio work and platform
audio details.

Top-level surfaces:

- `lib/main.dart`: app bootstrapping and global initialization
- `lib/screens/`: route-level product screens
- `lib/widgets/`: reusable UI and large embedded surfaces
- `lib/helpers/`: application services and workflow helpers
- `lib/models/`: shared app data models
- `lib/ai/`: chat, AI actions, local models, and cloud AI orchestration
- `juce_audio_engine/`: Flutter plugin and native JUCE implementation
- `backend/app_api/`: authenticated app backend
- `backend/llm_proxy/`: AI proxy and model/tool contract
- `admin_site/`: employee-facing operational UI

## Main Client Areas

### Projects

Entry points:

- `lib/screens/projects.dart`
- `lib/helpers/project_manager.dart`
- `lib/helpers/cloud_project_service.dart`
- `lib/helpers/project_version_store.dart`

The projects surface owns project list UX, project open/create flows, local
project metadata, and cloud sync touchpoints.

### Audio Editor

Entry points:

- `lib/screens/audio_editor.dart`
- `lib/screens/audio_timeline_pro.dart`
- `lib/widgets/effects_panel.dart`
- `lib/widgets/sample_browser_panel.dart`
- `lib/helpers/audio_project_persistence.dart`

The editor owns timeline UX, clip and row editing, import/export entry points,
AI-assisted production workflows, and most user-facing audio production state.

### Account And Auth

Entry points:

- `lib/screens/auth_gate.dart`
- `lib/screens/login.dart`
- `lib/screens/account.dart`
- `lib/helpers/auth_service.dart`
- `lib/helpers/app_user_service.dart`
- `backend/app_api/src/handlers/api_auth.py`
- `backend/app_api/src/common/auth.py`

The client uses app API auth endpoints for modern app auth. Cognito remains in
the repo for employee auth and compatibility paths.

### AI

Entry points:

- `lib/ai/chat_pipeline.dart`
- `lib/ai/cloud_llm_service.dart`
- `lib/ai/v3/ai_v3_planner_service.dart`
- `lib/ai/project_state_builder.dart`
- `lib/ai/assistant_action_timeline_reducer.dart`
- `backend/llm_proxy/src/handlers/api_responses.py`
- `backend/llm_proxy/src/handlers/api_mix_resolve.py`

The Flutter app builds deterministic project facts and executes validated
actions. Backend contract v3 owns V3 semantic instructions, the canonical
provider tool schema, model/runtime policy, and provider calls. It matches the
reverted-main V3 behavior and excludes the reverted PR #27 AI additions.
Updated clients send the context-only
`mixroom_v3_context_v1` contract through authenticated
`/v1/llm/v3/responses`; older released clients remain on the separately gated
legacy contract during migration. Adaptive, compact, retrieval, and capture
planners are not shipped in Flutter.

Current V3 commands are reversible and explicitly classified for immediate
local execution. The client prepares the complete plan, rechecks its state
digest, executes one atomic transaction, verifies exact readback, and only then
adds the completion receipt to chat. The existing pending-plan UI remains
available for a future command explicitly classified as requiring confirmation.

## Backend Areas

### App API

`backend/app_api` handles users, auth, entitlements, billing, feedback,
collaboration, admin APIs, feature flags, project telemetry, and webhooks.

### LLM Proxy

`backend/llm_proxy` handles cloud AI requests. Keep model/provider behavior
server-side unless there is a deliberate local-only feature.

### Admin Site

`admin_site` is an employee-facing operational surface. It should use admin API
contracts rather than duplicating backend business logic.

## Rule Of Thumb

Put UI state near the screen, workflow state in helpers/services, persistent
shape in models, and low-latency audio behavior in the engine. If a change needs
the Flutter app and the engine to agree on behavior, document the method-channel
contract in [Flutter/native bridge](flutter_native_bridge.md).
