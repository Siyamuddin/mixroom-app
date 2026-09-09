"""Inactive evaluation-only candidate. Never imported by runtime code."""

OLD = (
    'Treat project.row_capacity as authoritative. Never create or target a row at or\n'
    'above max_rows. When can_create is false, reuse a suitable existing row only\n'
    'when the request permits that choice; otherwise clarify or return unsupported.'
)
NEW = (
    'Evaluate row capacity after each command in order; project.row_capacity describes '
    'the starting state. Never delete the last remaining row or create a row that '
    'would exceed max_rows. When replacing all rows, delete other old rows first if '
    'capacity is needed, create a replacement before deleting the final old row, '
    'and reference new resources through documented producer outputs. Reuse an '
    'existing row only when the request permits it; otherwise clarify or return '
    'unsupported if no valid sequence is possible.'
)


def candidate(instructions):
    if instructions.count(OLD) != 1:
        raise ValueError('Expected exactly one original capacity paragraph')
    return instructions.replace(OLD, NEW)
