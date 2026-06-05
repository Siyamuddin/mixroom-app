# Mixroom Engineering Docs

Owner: Engineering  
Status: Living docs  
Last reviewed: 2026-06-04

This section is the technical onboarding path for Mixroom. Keep it close to the
code, short enough to read, and specific enough that a new developer can ship a
small change without relying on oral history.

Every page has an owner and update trigger. If a change touches one of the
watched code areas in `docs/engineering/docs_manifest.json`, update the matching
page in the same commit or record why the doc still holds.

## Start Here

1. [Local setup](local_setup.md)
2. [App architecture](app_architecture.md)
3. [Audio engine architecture](audio_engine_architecture.md)
4. [Flutter/native bridge](flutter_native_bridge.md)
5. [Testing and debugging playbook](testing_debugging_playbook.md)

## Core Reference

- [Auth and account flows](auth_account_flows.md)
- [Project and file model](project_file_model.md)
- [Build and release process](build_release_process.md)
- [Known platform issues](known_platform_issues.md)
- [How to add a feature](how_to_add_a_feature.md)
- [Architecture decisions](adr/README.md)

## Docs Freshness Check

Run this before opening a PR or cutting a release:

```bash
dart run tool/check_docs_freshness.dart --base origin/main
```

Run this before committing staged changes:

```bash
dart run tool/check_docs_freshness.dart --staged
```

To enable repo-owned Git hooks for this checkout:

```bash
git config core.hooksPath tool/git-hooks
```

That enables:

- `pre-commit`: checks staged files.
- `pre-push`: checks changes against the configured upstream branch.

The checker is intentionally conservative. It does not decide whether the docs
are correct. It flags code changes that normally require a human to review the
matching documentation.
