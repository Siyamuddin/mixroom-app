# macOS input-channel discovery

This locally authorized follow-up uses CoreAudio input capacity and optional
channel names for the selected input UID, or the current System Default input.
It does not infer capacity from the output, open channel masks, or saved routes.

The two existing channel-menu locations share the same widget and policy:
numbered mono inputs, complete non-overlapping stereo pairs, a visible read-only
mono selection, and explicit unavailable/loading states. The selected track's
saved channel range is authoritative. Refresh does not rewrite it. Choosing a
replacement updates the track and schedules the existing autosave.

An explicitly selected missing device stays selected but unavailable; it no
longer silently becomes System Default. Input changes refresh through the
existing native owner/event channel, with separate callback tuples so capture
listener cleanup cannot remove discovery observers. Refreshes are coalesced and
superseded results discarded. Input-only discovery does not open capture or
reconfigure playback.

Recording and monitoring reject invalid ranges, verify the prepared device
identity and capacity, and use existing playback recovery on preparation
mismatches. macOS's old 32-channel index limit was removed: the existing AUHAL
channel map captures only the requested mono/stereo channels. Native validation
still checks physical capacity, integer bounds, and post-preparation capacity.
Other platforms keep their existing selection policy and project format.

## Verification

- Policy/widget tests cover physical capacities, odd channel counts, named and
  unnamed channels, missing devices, invalid saved stereo routes, track changes,
  disabled controls, and unavailable metadata.
- Real-editor integration with controlled inventories passes: saved Inputs 7–8
  remain unavailable on a smaller input; stale refreshes lose to newer events;
  explicit replacements survive a capacity shrink; discovery starts no capture.
- Existing real macOS project-open/audio-meter/recording recovery integration
  passed alongside the new input integration.
- macOS native build passes with existing compiler warnings. Shared platform,
  sample-rate and input tests pass; existing editor analyzer diagnostics remain.
- A real multi-channel interface and its channel names still need studio
  acceptance. Simulated inventories do not replace that physical check.

All input-channel work remains local. No push, PR, or external issue creation is
authorized for these changes.
