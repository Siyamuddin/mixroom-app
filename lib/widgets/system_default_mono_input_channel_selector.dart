import 'package:flutter/material.dart';

class SystemDefaultMonoInputChannelSelector extends StatelessWidget {
  const SystemDefaultMonoInputChannelSelector({
    super.key,
    required this.configurationKnown,
    required this.inputAvailable,
    required this.supportedStart,
    required this.supportedCount,
    required this.start,
    required this.count,
    required this.enabled,
    required this.decoration,
    required this.onUseSupportedInput,
    this.loading = false,
  });

  final bool configurationKnown;
  final bool? inputAvailable;
  final int supportedStart;
  final int supportedCount;
  final int start;
  final int count;
  final bool enabled;
  final InputDecoration decoration;
  final VoidCallback onUseSupportedInput;
  final bool loading;

  String get supportedLabel => 'Input ${supportedStart + 1} (Mono)';

  @override
  Widget build(BuildContext context) {
    final valid =
        configurationKnown &&
        start == supportedStart &&
        count == supportedCount;
    final saved = count == 1
        ? 'Input ${start + 1}'
        : 'Inputs ${start + 1}–${start + count}';
    return InputDecorator(
      decoration: decoration.copyWith(
        helperText: inputAvailable == false
            ? 'No input device available'
            : configurationKnown && !valid
            ? 'Choose the supported input before recording or monitoring.'
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              !configurationKnown
                  ? loading
                        ? 'Loading input information…'
                        : 'Input information unavailable'
                  : valid
                  ? supportedLabel
                  : '$saved — Unavailable',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (configurationKnown && !valid)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13),
              ),
              onPressed: enabled ? onUseSupportedInput : null,
              child: Text('Use $supportedLabel'),
            ),
        ],
      ),
    );
  }
}
