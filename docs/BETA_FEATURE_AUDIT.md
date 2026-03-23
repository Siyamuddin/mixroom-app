# Beta Feature Audit

This is a practical beta-status pass against the large master TODO list.
It is intentionally biased toward launch blockers, not long-tail ideas.

## Built or mostly built

- Accounts / auth:
  - App-side Cognito auth gate, email auth, social auth plumbing, session restore, and sign-out flow exist.
  - Remaining work is mostly AWS/provider configuration and real-device QA.

- Core project UX:
  - DAW project rename inside project settings already exists.
  - The first-exit untitled-project naming flow was fixed so fresh untitled projects actually require explicit name confirmation, and that confirmation now reuses the real folder-rename path.
  - System back now routes through the same editor back/save flow instead of relying only on the toolbar back button.

- Chat backend path:
  - App supports authenticated AWS proxy mode.
  - Lambda proxy now owns the production prompt/tool/model contract server-side.
  - Remaining work is AWS deployment and secret/provider setup.

- Chat UX:
  - Audio and active video chatbars were tightened for typography/spacing.
  - The active video editor no longer shows stale `CapCut` branding in the chat bar.
  - Mixing execution now prefers the LLM `assistant_message` instead of always stacking hard-coded per-action summary bubbles on top of it.

- Audio export:
  - Export UI and render path already exist.
  - Saved filename and export-success file-opening flow were tightened in this pass.
  - Remaining work is device QA and audio correctness regression testing.

- Piano roll / MIDI editing:
  - Piano roll editor exists.
  - MIDI compose/chop assistant actions exist.
  - Bundled SFZ instrument catalog exists.
  - Remaining work is controller/device QA and UX polish.

- Add/delete many tracks:
  - Row add/delete flow exists.
  - Current max row cap is 100 in the app.

- Stem separation:
  - Spleeter-backed separator exists.

- Subscription foundation:
  - Client entitlement service exists.
  - In-house AWS app API scaffold exists for auth, users, entitlements, and billing.
  - This is not required to launch beta if everyone stays on free tier.

- Video editor:
  - A large video editor implementation already exists.
  - The active editor is `video_editor_sequencer.dart`, not `video_editor2.dart`.
  - Export save/open flow is already wired in that active file.
  - This is not required for beta launch.

- Localization wiring:
  - App-level locale now listens to `LocaleProvider`, so later language changes propagate through `MaterialApp` instead of only the initial locale snapshot.

## Still incomplete for beta

- Learned AI mixing model rollout:
  - ONNX inference path exists.
  - Default feature flag is still off.
  - Trained ONNX assets are not enabled in `pubspec.yaml` by default.
  - This still needs real training data, model export, asset copy, and validation.

- Gain staging UI:
  - Not confirmed by audit.
  - Treat as still pending unless manual QA shows it already exists in a release-ready state.

- Performance / thermal stabilization:
  - Your previously identified playback, timeline, and EQ analyzer hotspots are still the highest code-side optimization targets.
  - This remains a beta blocker for real sessions.

- Android / Bluetooth readiness:
  - Bluetooth and AirPods issues from the master list are not closed by this audit.
  - Treat as pending QA/fix work.

- Export regression testing:
  - The feature exists, but stretched clips, Android/iOS cross-open, and saved-file behavior still need explicit test passes.

## External-only work

- OpenAI key rotation and secret storage
- AWS LLM proxy deployment
- Cognito hosted UI / callback / logout URLs
- Google / Apple / Kakao provider console setup
- Real-device auth smoke testing
- API rate limiting and production logging settings

See:

- [BETA_AWS_OPENAI_SETUP_CHECKLIST.md](BETA_AWS_OPENAI_SETUP_CHECKLIST.md)
- [BETA_AUTH_QA_CHECKLIST.md](BETA_AUTH_QA_CHECKLIST.md)

## Intentionally deferred from beta

- Payments and paid entitlement enforcement
- Cloud project storage / platform social features
- Website/platform upload polish
- MCP rewrite
- Video-editor expansion work beyond what already exists
- Gamification / education features
- Advanced marketplace / profile / follower-transfer ideas

## Suggested next code priorities

1. Learned mixing model enablement path:
   - export real ONNX models
   - enable assets
   - run validation on representative projects
2. Performance stabilization:
   - transport rebuild pressure
   - timeline playback repaint loop
   - EQ analyzer polling / paint cost
3. Android / Bluetooth beta QA and fixes
4. Export regression matrix on real devices
