# Local review results

Review fixes tested on 2026-09-14, using the supplied historical exports and recent
Untitled Project #34 / pro83-test captures. No deployment or production model replacement.

- The corpus yielded 371 continuous targets and 546 selection examples across five
  project groups. Selection labels: 528 retained, 18 rejected/reverted. All negative
  examples came from one project. Duplicate historical downloads were deduplicated.
- Both exported ONNX files passed training/runtime feature checks and sklearn/ONNX
  prediction parity. A regression test trained with a captured hashed third-party
  plugin ID and applied both models to the corresponding raw runtime path.
- The local HTTP backend replayed all 917 examples without fallback. It exercised
  selection, magnitude adjustment and suppression of dependent FX actions. Mean
  resolver duration was under 2 ms per request, with a 14 ms maximum in this run.
  These are local measurements, not production latency guarantees.
- Leaving out each project produced four testable folds. Normalized magnitude error
  decreased in all four. Selection retained 86.7%, 100%, 100% and 90.6% of their
  positive examples, compared with 100% from the baseline. Holding out the project
  containing all negatives correctly refused training because only one class remained.

This candidate is **development only**. The results do not establish better mixing:
selection regressed on two folds, rejection generalization remains unmeasurable,
and overlap with the original baseline training corpus is not fully known. Normal
training requires each class across multiple independent songs, followed by held-out
evaluation and listening tests. Keep production models unchanged until those pass.

Validation: 77 training tests, 11 resolver/API tests, 13 producer backend tests and
26 Flutter capture tests passed. The macOS debug build also passed.

## Plugin identity follow-up

New snapshots carry a path-independent model identity qualified by native plugin
format, vendor, name, UID and version. Engine loading IDs remain unchanged. The
macOS native build passed; 78 training tests, 11 resolver/API tests and 28 Flutter
capture tests passed. Regression tests exported both ONNX models from one install
path and exercised them against another, rejected a distinct plugin identity, and
verified older path-hash models still work when runtime supplies new metadata.
Android and Windows bridge signatures were updated but not built on this Mac.
A real third-party plugin installation test on each shipping platform remains part
of release review; automated tests use controlled plugin metadata.
