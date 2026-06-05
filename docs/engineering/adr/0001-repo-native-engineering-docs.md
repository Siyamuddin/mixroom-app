# 0001: Keep Engineering Docs In The Repo

Status: Accepted  
Date: 2026-06-04  
Owner: Engineering  
Update trigger: Revisit this if the team adopts an external docs platform as
the canonical engineering source of truth.

## Context

The most important technical documentation needs to stay close to the code so it changes with the system and can be reviewed in the same workflow as implementation changes.

## Decision

Engineering docs live in `docs/engineering/` as Markdown. Each page declares an
owner and update trigger. `docs/engineering/docs_manifest.json` maps code areas
to docs, and `tool/check_docs_freshness.dart` flags changes that likely require
documentation review.

## Consequences

Docs can be reviewed with code and kept versioned with the repo. The tradeoff is
that Markdown is less polished than a dedicated docs product. If the team later
wants a richer visual site, these files can feed GitBook, Mintlify, Docusaurus,
MkDocs, or another static docs renderer.

