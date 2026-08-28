# Project And File Model

Owner: Engineering  
Status: Draft  
Last reviewed: 2026-08-29
Update trigger: Update this when project schema, clip storage, waveform
storage, asset import, backup/recovery, cloud sync, collaboration, or export
file behavior changes.

## Purpose

Mixroom projects combine timeline state, audio assets, generated data,
preferences, undo/recovery metadata, and optional cloud-facing state. This page
points to the code that owns those concerns and records the invariants that
should not drift.

## Client Entry Points

- `lib/helpers/project_manager.dart`
- `lib/helpers/audio_project_persistence.dart`
- `lib/helpers/project_version_store.dart`
- `lib/helpers/project_version_preferences.dart`
- `lib/helpers/project_undo_history_store.dart`
- `lib/helpers/cloud_project_service.dart`
- `lib/helpers/cloud_sync_preferences.dart`
- `lib/helpers/audio_export_plan.dart`
- `lib/helpers/export_save_dialog.dart`
- `lib/models/`
- `lib/screens/projects.dart`
- `lib/screens/audio_editor.dart`
- `lib/screens/audio_timeline_pro.dart`

## Backend Entry Points

- `backend/app_api/src/handlers/api_project_telemetry.py`
- `backend/app_api/src/handlers/api_collaboration.py`
- `backend/app_api/src/common/cloud_object_storage.py`
- `backend/app_api/src/common/collaboration_repository.py`
- `backend/app_api/src/common/project_telemetry_repository.py`

## What A Project Contains

A project can include:

- project name and metadata
- BPM, key, tempo mode, and timeline settings
- rows, clips, MIDI notes, automation, and effect state
- source audio files and generated audio files
- waveform and analysis data
- undo history and recovery metadata
- AI chat history and project context
- local/cloud sync preferences

Use the model and persistence code as the source of truth for exact field names.
This page should describe ownership and invariants, not duplicate every
serialized key.

## File Ownership Rules

- Project state should remain recoverable after app restart.
- Imported audio must have a stable project-owned location or a documented
  external-file dependency.
- Generated/exported files need clear naming and user-visible save/share
  behavior.
- Missing files should produce recoverable project-open behavior where possible.
- Schema or migration changes need tests or a manual migration check using an
  older project.

Action-first V3 execution does not introduce a project schema. Verified local
changes enter the existing compound Undo history and persistence path; failed
or rolled-back work must not be saved as a successful assistant completion.
PRO-62 moves V3 semantic planning to the backend but preserves client-side
project-context collection and the existing persistence and Undo boundaries.
No project-file field or migration is introduced by that cutover.

## Export Interaction

Export is both an engine concern and a project/file concern. The engine renders.
The app chooses destination, format options, and post-export UX. Update this
page when export changes saved file names, file extensions, output folders,
share behavior, or recovery behavior after a failed export.

## Cloud Sync And Collaboration

Cloud sync and collaboration must treat local project files and cloud object
storage as separate responsibilities. Keep identity, access control, and object
paths documented when those flows change.
