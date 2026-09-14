import 'package:flutter/material.dart';
import '../helpers/mac_input_channel_policy.dart';

class MacInputChannelSelector extends StatelessWidget {
  const MacInputChannelSelector({
    super.key,
    required this.capacity,
    required this.names,
    required this.selection,
    required this.enabled,
    required this.status,
    required this.decoration,
    required this.onChanged,
    this.dropdownColor,
  });
  final int capacity;
  final List<String> names;
  final MacInputChannelOption selection;
  final bool enabled;

  /// Null when capabilities are known; otherwise the user-facing state.
  final String? status;
  final InputDecoration decoration;
  final Color? dropdownColor;
  final ValueChanged<MacInputChannelOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = status == null
        ? macInputChannelOptions(capacity)
        : <MacInputChannelOption>[];
    final valid = options.contains(selection);
    final message =
        status ?? (options.isEmpty ? 'No input channels available' : null);
    if (message != null || (capacity == 1 && valid)) {
      return InputDecorator(
        decoration: message != null && !message.startsWith('Loading')
            ? decoration.copyWith(
                helperText: '${selection.label(const [])} — Unavailable',
              )
            : decoration,
        child: Text(
          message ?? '${selection.label(names)} (Mono)',
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    return DropdownButtonFormField<MacInputChannelOption>(
      key: ValueKey(Object.hash(capacity, selection, names.join('|'))),
      initialValue: selection,
      isExpanded: true,
      dropdownColor: dropdownColor,
      style: const TextStyle(color: Colors.white),
      decoration: decoration.copyWith(
        helperText: valid
            ? null
            : 'Choose an available input before recording or monitoring.',
      ),
      items: [
        if (!valid)
          DropdownMenuItem(
            value: selection,
            enabled: false,
            child: Text('${selection.label(const [])} — Unavailable'),
          ),
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(option.label(names), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: !enabled
          ? null
          : (value) {
              if (value != null && options.contains(value)) onChanged(value);
            },
    );
  }
}
