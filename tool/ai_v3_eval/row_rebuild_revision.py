"""Locally adopted 16/20 wording; evaluation helpers, no runtime imports."""
from row_rebuild_candidate import NEW as PREVIOUS_CAPACITY, OLD as ORIGINAL_CAPACITY
from pitch_candidate import OLD as ORIGINAL_PITCH

CAPACITY = (
    'Plan commands against the evolving project state, not just the starting snapshot. '
    'After every command, at least one row must remain and the row count must not exceed '
    'a known max_rows. Starting can_create does not describe capacity after deletions. '
    'For a complete rebuild, retain one old row, delete only other rows the user authorized '
    'removing, create a replacement when capacity permits, then delete the retained old row. '
    'Continue creating replacements only within the remaining capacity. Preserve protected '
    'rows and clips, reference new resources through documented producer outputs, and provide '
    'the requested MIDI parts for replacement instrument rows within the command budget. '
    'If no valid sequence exists, reuse an existing row only when permitted; otherwise clarify.'
)
PITCH = (
    'For each MIDI command, resolve its effective instrument after preceding row creation '
    'and instrument changes. Choose the musical register and voicing within that instrument’s '
    'advertised playable_pitch_ranges before writing notes. Every note in create, replace, '
    'and append commands must belong to an inclusive allowed interval; gaps are unavailable. '
    'A bass role, genre, or style request does not override these limits or authorize changing '
    'a requested instrument. Clarify only when the requested result cannot be achieved with '
    'supported operations.'
)


def replace_once(text, original, replacement):
    if text.count(original) != 1:
        raise ValueError('Expected exactly one source paragraph')
    return text.replace(original, replacement)


def revise_capacity(text):
    return replace_once(text, PREVIOUS_CAPACITY, CAPACITY)


def revise_pitch(text):
    return replace_once(text, ORIGINAL_PITCH, PITCH)


def candidate(text):
    return revise_pitch(revise_capacity(text))


def historical_instructions(text):
    """Reconstruct pre-adoption wording for existing historical comparisons only."""
    if CAPACITY in text or PITCH in text:
        return replace_once(replace_once(text, CAPACITY, ORIGINAL_CAPACITY),
                            PITCH, ORIGINAL_PITCH)
    if text.count(ORIGINAL_CAPACITY) != 1 or text.count(ORIGINAL_PITCH) != 1:
        raise ValueError('Unknown historical instruction source')
    return text
