# iOS system-route audio behavior

iOS follows the active `AVAudioSession` output rate. Project loading and
buffer-only changes pass `preferredSampleRateHz: 0`, so a saved project rate is
metadata rather than a request to change the current route. Route notifications,
including a clock change on the same output, use the existing serialized route
coordinator. The editor publishes a rate only after the session, route, JUCE
device, processing graph, generation, and callback agree. Other valid rates are
displayed without restricting them to desktop presets where the existing wide
settings layout exposes that read-only diagnostic. The compact mobile Audio
Routing UI remains unchanged and does not expose sample-rate or buffer controls.
A positive native
compatibility request applies to its current transition and does not become the
next route's preference.

The current iOS V2 recording implementation supports System Default, Input 1
mono. A passive query reports that capability without activating capture,
changing the audio-session category, selecting an input, or changing Bluetooth
mode. The resolved device name is shown only when it is reliable; active-route
verification is cleared when capture ends.

Both input controls use the shared System Default mono selector. Valid tracks
show read-only **Input 1 (Mono)**. Saved stereo or higher-channel routes remain
visible as unavailable, and **Use Input 1 (Mono)** explicitly replaces only the
selected track and schedules autosave. Playback remains available. Recording and
monitoring reject an incompatible range before any session mutation and verify
the exact mono route again after preparation and before capture becomes active.
The Bluetooth HFP path no longer rewrites an arbitrary saved range to mono.

Input-only route changes use the existing native observer owner and event
channel. Dart refreshes are coalesced and stale results are discarded. Passive
unknown input availability allows permission and native preparation to resolve
the route; confirmed absence, loading, and an incompatible saved route remain
separate UI states.

## Verification

- Focused Dart policy, widget, route, and native-contract tests cover automatic
  rate mode, unusual/unknown rates, explicit input replacement, selected-track
  persistence, exact native mono enforcement, stale refreshes, and input-only
  events.
- The unsigned iOS device build succeeds with the Objective-C and JUCE changes.
- Android selector tests are included because iOS shares its System Default mono
  widget; Android behavior remains unchanged.
- Physical iPad checks passed for built-in 48 kHz playback, Input 1 mono
  recording and monitoring, Bluetooth media playback at 44.1 kHz, Bluetooth HFP
  mono recording at 16 kHz, restoration to 44.1 kHz stereo media playback, and
  disconnection recovery to the iPad's 48 kHz stereo output. Bluetooth input
  monitoring remains unavailable by the existing capture policy. Interruption
  fault injection, physical invalid-route replacement, and USB-interface
  behavior remain pending; automated tests cover the corresponding policy and
  recovery boundaries.

All work is local. No push, PR, or external issue creation is authorized.
