# Mixroom Weekly Plan Resolution: June 2026

Owner: Product and Engineering
Status: Implemented items plus decisions required
Last reviewed: 2026-07-10

## Resolution Summary

| Item | Resolution | Status |
| --- | --- | --- |
| Sped-up audio while moving the timeline | Touch pan and zoom no longer seek continuously. Audio stays parked during navigation and the transport seeks once when the gesture ends. | Implemented |
| Multi-select for audio clips | Select now has a touch-first workflow: long-press the first clip, tap more clips, then move, copy, duplicate, or delete the group. Empty-space lasso remains available. | Implemented |
| Grid over audio regions | Foreground grid rendering is enabled by default and can be toggled from the timeline tool menu. | Implemented |
| Android file browser intermittently shows empty folders | Shared-storage permission is requested as soon as a folder is selected. Transient empty reads retry, refresh requests cannot be lost behind an active read, cached-empty folders reload when expanded, and expanded folders refresh when the app resumes. | Implemented |
| Anchor and transient auto-detection | Existing onset DSP is suitable as the analysis base. Product semantics and persistent clip data still need a decision before exposing automatic anchors. | Decision required |
| N-Track Studio benchmarking | Initial official-source inventory and Mixroom gap classification are below. | Completed, first pass |

## Anchor and Transient Detection Decision

Mixroom already decodes clips to mono 16 kHz audio, builds a spectral-flux onset envelope, and extracts spaced transient events for tempo and kick-analysis workflows. The missing work is not basic DSP. It is the clip-level contract and editing behavior.

Recommended contract:

1. Store analysis positions in source milliseconds so trim, reverse, and time-stretch remain non-destructive views of the same result.
2. Treat the first confident onset as the default snap anchor, but never move the clip automatically when analysis finishes.
3. Let users reset or override the anchor. Automatic detection should provide a default, not silently change an arrangement.
4. Show faint transient markers in normal timeline view and stronger markers only in clip-edit mode.
5. Cache results by source-asset hash plus detector version. Do not persist hundreds of derived markers directly inside every clip instance.
6. Snap split and clip movement to detected events only when transient snapping is explicitly enabled. Keep musical-grid snapping independent.

Decisions required before implementation:

- Is the anchor only a snap reference, or should changing it also change clip placement?
- Does transient snapping live under the current magnet control or use a separate mode?
- Should duplicated clips share source analysis and keep independent anchor overrides? Recommendation: yes.
- What marker-density presets should ship? Recommendation: Sparse, Balanced, Detailed, with Balanced as default.

## N-Track Studio Feature Inventory

This inventory uses n-Track's current official [mobile overview](https://ntrack.com/ios.php), [feature list](https://ntrack.com/features.php), [product overview](https://ntrack.com/digital-audio-workstation.php), and [user guide](https://ntrack.com/help/guide.en.html). It describes advertised product capabilities, not a hands-on quality assessment.

| Area | Verified n-Track capability | Mixroom position | Direction |
| --- | --- | --- | --- |
| Platforms and project continuity | iOS, Android, Windows, macOS, and Linux with desktop/mobile project exchange | Mobile/tablet are current public priority; desktop work exists but is not public | Follow later, not a mobile launch blocker |
| Audio and MIDI recording | Multitrack audio and MIDI recording, count-in, track arming, live processing, configurable recording quality | Audio and MIDI recording are present | Maintain; prioritize reliability over more controls |
| Takes | Multiple recordings can appear in take lanes | No equivalent take-lane workflow found | Follow, high value for vocal and instrument capture |
| Timeline editing | Region move/trim, fades, gain, mute, transpose, looping, and integrated region controls | Move, trim, split, stretch, reverse, gain, crossfade, clone, group actions | Follow clip fades and clip looping; preserve Mixroom's simpler surface |
| Multi-select | General DAW arrangement workflows support grouped region editing | Touch-first multi-select now implemented | Complete for current scope |
| Grid and quantize | Project grid and quantize controls | Musical grid, snap, and foreground grid | Mixroom now has a strong mobile editing presentation |
| MIDI composition | Piano roll, velocity and controller editing, MIDI recording | Piano roll, note tools, velocity, instrument editing, MIDI recording | Maintain |
| Step sequencing | Dedicated pattern-based step sequencer with velocity, swing, freerun, and playlist modes | No dedicated step sequencer found | Follow, high priority for portable sketching |
| Instruments and samplers | Instrument browser, drum/melodic/multilayer samplers, slicers, screen keyboard and drums | Instrument lanes, MIDI instruments, sampler creation, sample browser | Follow slicer and pad-first workflows only if they stay fast |
| Loop and sound library | Downloadable audio/MIDI loops, chords, beats, progressions, and a large sound catalog | Local sample browser and project insertion | Diverge: favor user library plus AI-assisted discovery over catalog size |
| Mixer and routing | Mixer strips, insert effects, aux sends/returns, track routing | Row/master effects, gain/pan, mute/solo, groups, automation | Follow sends/returns after mobile routing UX is defined |
| Automation | Volume, pan, sends/returns, and effect-parameter automation | Row/master automation, effect parameters, reusable automation clips and templates | Mixroom is competitive; differentiate through reusable patterns and AI creation |
| Effects | Broad built-in suite including dynamics, EQ, denoise, amps, pitch tools, VocalTune, harmonizers, vocoder, and creative effects | Broad built-in row/master effects and desktop external-plugin work | Follow only clear mobile jobs: denoise, de-ess, vocal tuning, amp workflows |
| Stem separation | AI MixSplit for vocals, bass, drums, and other | Stem separation actions exist | Maintain and connect more tightly to AI workflow |
| AI workflow | AI MixSplit is the primary advertised AI capability | Project-aware AI chat can explain, mix, edit, automate, work with MIDI, and trigger stems | Diverge and lead; this is Mixroom's strongest differentiation |
| Collaboration | Songtree discovery, overdub, upload, and version-tree workflow | Backend collaboration work exists, but no equivalent public creation network is documented | Diverge: project sharing first; avoid building a social network prematurely |
| Project browser | Dedicated song browser | Project browser, saving, recovery, versions, and cloud-related work | Maintain |
| Export and formats | Mixdown and broad desktop import/export/sync formats | WAV/MP3 export with quality, normalization, sharing, and platform handling | Maintain mobile essentials; defer interchange formats |
| Advanced desktop | Third-party plug-ins, synchronization, video, surround, deep routing | Desktop plug-in hosting work exists; mobile/tablet remain public priority | Do not copy into mobile scope |

## Adoption Priority

### Follow now

1. Take lanes with a simple comp/select flow.
2. Step sequencer optimized for quick drums and repeated patterns.
3. Clip fades and clip looping using direct manipulation.
4. Transient markers and anchor snapping after the contract above is approved.

### Follow later

1. Aux sends and returns.
2. Focused vocal tools such as de-essing and transparent tuning.
3. Slicer and pad workflows.
4. Cross-device project continuity when the public desktop product is ready.

### Diverge

1. Keep AI project-aware and action-oriented instead of treating stem separation as the whole AI story.
2. Prefer a fast user-library workflow over competing on downloadable catalog size.
3. Keep advanced desktop routing, surround, sync, and video out of the mobile/tablet core.
4. Treat collaboration as controlled project sharing before considering a public social network.

## Verification

- Widget test: touch timeline pan emits no seek during movement and exactly one seek on release.
- Widget test: tablet long-press selection adds another clip and group drag commits both clips.
- Widget test: foreground grid can be enabled and disabled from the timeline tool menu.
- Widget tests: transient empty directory reads recover, refresh requests made during an active read complete, cached-empty folders reload on re-expansion, and expanded folders refresh after app resume.
- Android build: debug APK packages successfully with the file-browser permission and refresh changes.
- Static analysis: the changed timeline file introduces no new analyzer errors.
