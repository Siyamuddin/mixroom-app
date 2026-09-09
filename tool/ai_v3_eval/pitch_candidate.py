"""Evaluation-only instruction candidate; never imported by the runtime."""
OLD = ('Treat commands as ordered state changes: after row.set_instrument,\n'
       'later MIDI commands on that row use the replacement instrument. When an instrument\n'
       'advertises playable_pitch_ranges, every generated MIDI pitch must be inside one of\n'
       'those ranges.')
NEW = ('For each MIDI command, resolve the effective instrument after preceding commands, '
       'including row.set_instrument. Choose the register and chord voicings within its '
       'advertised playable_pitch_ranges, respecting gaps. Preserve requested instruments; '
       'a style request does not authorize unavailable pitches or instrument substitution. '
       'Clarify only when the requested result cannot be achieved with supported operations.')

def candidate(instructions):
    if instructions.count(OLD) != 1:
        raise ValueError('Expected exactly one MIDI range paragraph')
    return instructions.replace(OLD, NEW)
