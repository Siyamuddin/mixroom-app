# How To Add A Feature

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-08-29
Update trigger: Update this when feature development workflow, review
expectations, test strategy, release gates, or code ownership changes.

## Purpose

This is the default path for a new developer adding a small or medium Mixroom
feature.

## Feature Path

1. Identify the owning surface.

   Use [App architecture](app_architecture.md) to decide whether the change
   belongs in a screen, widget, helper/service, model, backend handler, AI
   module, or the native audio engine.

2. Find the existing pattern.

   Prefer nearby code over introducing a new abstraction. Use current UI,
   service, and model patterns unless the feature clearly needs a new boundary.

3. Define the state owner.

   UI-only state belongs near the widget or screen. Workflow state belongs in a
   helper/service. Persistent shape belongs in models and persistence helpers.
   Low-latency audio state belongs in the engine.

4. Add the narrow implementation.

   Keep the first version small. Avoid changing unrelated behavior while adding
   the feature.

5. Add tests proportional to risk.

   Use targeted Flutter tests for UI and workflow behavior. Use backend tests
   for API contracts and authorization. Use manual platform QA for audio,
   recording, permissions, billing, auth, and export behavior.

6. Update docs in the same change.

   Run:

   ```bash
   dart run tool/check_docs_freshness.dart --staged
   ```

   If the checker flags docs, update them or record why the existing doc still
   applies.

   The README points to platform setup details, including the automatic iOS
   JUCE archive selection in the audio engine podspec.

7. Check release impact.

   If the feature touches auth, billing, analytics, permissions, user data, AI,
   export, bundled assets, native audio, or store-facing behavior, update the
   release and compliance docs.

   AI planning semantics, prompts, tool descriptions, and provider policy must
   live on the backend. Flutter may retain only factual context collection,
   the executable wire contract, and deterministic safety validation. Run the
   AI IP boundary scanner against source and every release-equivalent artifact.

## Done Means

- The feature works on the intended platforms.
- The code follows local patterns.
- Relevant tests pass.
- The docs that explain the changed behavior are current.
- Release risks are explicit.
