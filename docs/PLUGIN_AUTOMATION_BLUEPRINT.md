# Plugin Automation Blueprint (DAW-Grade)

## Goal
Add full automation for any plugin parameter (row + master), while preserving the existing row volume automation and enabling FL-style reusable automation patterns.

## Current Baseline (as of this branch)
- Row volume automation exists as per-row point lists in Flutter (`_rowVolumeAutomation`) and is rendered in the expanded row volume panel.
- iOS JUCE engine applies row volume automation in the audio graph (`VolumeAutomationProcessor`).
- Android bridge currently no-ops `setTrackAutomationPoints` (no audio-thread automation engine).
- Plugin parameters are exposed via track/master parameter APIs and can be edited live from the effects panel.

## Product Decision: Hybrid UX (Recommended)
Use both:
1. **Lane editing in expanded row panel** for precision and fast local edits.
2. **Automation clips on timeline** for reusable patterns, copy/paste, and arrangement-level workflow.

This matches serious DAW behavior:
- Fast parameter drawing without leaving the track context.
- Reusable clip patterns (duplicate, move, stretch) like FL automation clips.

## UX Spec

### 1) Automation Entry
- Add an `Automation` tab in expanded row header (next to `Volume` and `Effects`).
- Within the tab:
  - `Target` picker (Volume + armed plugin parameters for that row).
  - `Show On Timeline` toggle per target.
  - Lane editor (points, ramps, curve shape).

### 2) Parameter Arming
- In effects panel, each automatable parameter gets an `Arm` control.
- Armed parameters appear in the row automation target picker.
- Default view shows only armed parameters to avoid clutter.

### 3) Timeline Automation Clips
- Add `Automation Clips` layer in timeline.
- Clip is tied to one automation target.
- Supports: create, duplicate, copy/paste, move, trim, stretch, mute.
- Visuals:
  - Per-target color.
  - Compact waveform-like envelope preview inside clip.
  - Optional ghost display of resolved lane value on row.

### 4) Write/Read Modes
- Transport automation mode per project:
  - `Read` (playback only)
  - `Touch`
  - `Latch`
  - `Write`
- While playing in write-capable modes, moving a knob writes points into the armed lane/clip.

### 5) Conflict Rules
- Evaluation order at time `t`:
  1. Base parameter value (current preset/state)
  2. Lane baseline curve
  3. Active automation clips (sum/replace by mode)
- Start simple with `Replace` mode; add additive modes later.

## Data Model
Introduce generic automation models (separate from current volume-only points):

```dart
class AutomationTarget {
  String laneId;           // stable UUID
  String scope;            // row | master
  int row;                 // for row scope
  int effectIndex;         // -1 for row volume/gain style targets
  String paramId;          // stable plugin param id
  String displayName;
  String unit;             // dB, %, Hz, enum, bool
  String type;             // float | bool | choice
  double min;
  double max;
  dynamic defaultValue;
}

class AutomationPointV2 {
  double timeMs;           // absolute (lane) or relative (clip)
  double value;            // normalized 0..1 for engine
  String curve;            // step | linear | bezier (phase 1: linear)
}

class AutomationClip {
  String id;
  String laneId;
  int row;
  double startMs;
  double lengthMs;
  bool muted;
  List<AutomationPointV2> points; // relative 0..lengthMs
}
```

## Native/Engine Architecture

### Core Requirement
Automation playback must run in native engine time, not from Dart timers.

### Engine Responsibilities
- Hold lane/clip automation state.
- Resolve value per target each audio block.
- Apply to:
  - row volume/gain target
  - row plugin parameter target
  - master plugin parameter target

### Parameter Target Resolution
- Bind by stable `paramId` first.
- Fallback to parameter display name only for backward compatibility.

### Platform Parity
- iOS already has row automation processor; extend to generic target automation.
- Android must gain equivalent engine-side automation path (current no-op prevents DAW-grade parity).

## Migration Strategy
1. Keep existing row volume automation as legacy source.
2. On load, migrate legacy points to automation lane `row/<row>/volume`.
3. Save both formats during transition window; later deprecate legacy-only path.

## Implementation Phases

### Phase 1 (Foundation)
- Add stable parameter IDs end-to-end.
- Add generic automation data models and JSON schema.
- Add automation target picker in UI.
- Support one selected lane editing in expanded row panel.

### Phase 2 (Timeline Clips)
- Add automation clip entities + rendering.
- Reuse clip editing interactions (duplicate, cut, paste, move, stretch).
- Add lane/clip conflict resolution (`Replace` mode).

### Phase 3 (Write Modes)
- Add read/touch/latch/write.
- Capture parameter gestures during playback and write points.
- Quantize/smoothing options.

### Phase 4 (Parity + Polish)
- Android native parity.
- Performance pass (cache bound parameters, reduce UI churn).
- UX polish (target search, lane folders, color system, hide/show).

## Immediate Next Build Target
Ship Phase 1 with:
- Stable param IDs
- Expanded-row Automation tab
- Single-lane automation editing for any armed row plugin parameter

Then add timeline automation clips in Phase 2 for FL-style pattern workflows.
