enum DesktopMidiKeyAction { ignored, noteOn, noteOff }

DesktopMidiKeyAction transitionDesktopMidiKey<T>({
  required Set<T> heldKeys,
  required T key,
  required bool isKeyDown,
  required bool isKeyRepeat,
  required bool isKeyUp,
  required bool canStartNote,
}) {
  if (isKeyUp) {
    return heldKeys.remove(key)
        ? DesktopMidiKeyAction.noteOff
        : DesktopMidiKeyAction.ignored;
  }

  if ((isKeyDown || isKeyRepeat) && canStartNote && heldKeys.add(key)) {
    return DesktopMidiKeyAction.noteOn;
  }

  return DesktopMidiKeyAction.ignored;
}
