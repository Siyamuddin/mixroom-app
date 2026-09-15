# PR review checklist

- [ ] Capture a normal mixing session without AI prompts, including levels and FX parameters. Stop and submit an honest outcome. Playback, undo and saving still work.
- [ ] Stop capture and submit. Check preparing, upload progress, verification, then uploaded confirmation. Interrupt the connection and reopen the project; unfinished uploads resume. With no pending uploads, no retry timer runs.
- [ ] Run the [local training guide](PRO-20-local-test.md) with recent and original captures. Check target counts, exclusions and deduplication; originals remain unchanged.
- [ ] Confirm the output contains two ONNX models, both models are retrained and classifier labels include observed positives/negatives, and feature/export parity checks pass.
- [ ] Launch the local backend and app. Confirm `mix_magnitude_human_v3`, `human_magnitude` decisions, valid control values and no resolver fallback. Verify selection can reject an action and suppress dependent plugin edits. Check unknown effects and reset requests too.
- [ ] Compare against the current model on independent songs, review coverage and errors, then blind-listen to identical requests. Small-corpus development results do not establish improvement.
- [ ] Check third-party plugins: the same plugin/version at different install paths shares `modelPluginId`; distinct plugins/versions stay separate. Existing path-hash models still work for their original paths. Newly inserted hosted plugins retain planner settings until a later request has loaded instance metadata; a matching display name alone never authorizes learned changes.
- [ ] Run the documented regression tests. No backend deployment or model promotion is part of this local review.
