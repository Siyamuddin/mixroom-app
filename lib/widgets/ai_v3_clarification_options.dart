import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';

typedef AiV3ClarificationSubmit = Future<bool> Function(String response);

class AiV3ClarificationSession {
  String? _activeId;

  String? get activeId => _activeId;

  void activate(String clarificationId) {
    _activeId = clarificationId;
  }

  bool resolve(String? clarificationId) {
    if (clarificationId == null || _activeId != clarificationId) return false;
    _activeId = null;
    return true;
  }

  void clear() {
    _activeId = null;
  }
}

class AiV3ClarificationOptions extends StatefulWidget {
  const AiV3ClarificationOptions({
    super.key,
    required this.options,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
  });

  final List<String> options;
  final bool busy;
  final AiV3ClarificationSubmit onSubmit;
  final VoidCallback onCancel;

  @override
  State<AiV3ClarificationOptions> createState() =>
      _AiV3ClarificationOptionsState();
}

class _AiV3ClarificationOptionsState extends State<AiV3ClarificationOptions> {
  final TextEditingController _customController = TextEditingController();
  final FocusNode _customFocusNode = FocusNode();
  bool _showCustomResponse = false;
  bool _submitting = false;

  bool get _disabled => widget.busy || _submitting;

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  void _showCustomField() {
    if (_disabled || _showCustomResponse) return;
    setState(() => _showCustomResponse = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _customFocusNode.requestFocus();
    });
  }

  Future<void> _submit(String response) async {
    final normalized = response.trim();
    if (_disabled || normalized.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(normalized);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  ButtonStyle _optionStyle() {
    return TextButton.styleFrom(
      alignment: Alignment.centerLeft,
      minimumSize: const Size(double.infinity, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      foregroundColor: const Color(0xFFF4F4F4),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      disabledForegroundColor: Colors.white38,
      disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final somethingElse = L10n.translate(context, 'Something else…');
    final describeResponse = L10n.translate(context, 'Describe what you want');
    final sendResponse = L10n.translate(context, 'Send response');
    final cancel = L10n.translate(context, 'Cancel');

    return Column(
      key: const ValueKey<String>('ai_v3_clarification_options'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < widget.options.length; index++) ...[
          Semantics(
            button: true,
            enabled: !_disabled,
            label: widget.options[index],
            child: TextButton(
              key: ValueKey<String>('ai_v3_clarification_option_$index'),
              onPressed: _disabled
                  ? null
                  : () => _submit(widget.options[index]),
              style: _optionStyle(),
              child: Text(
                widget.options[index],
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
        ],
        Semantics(
          button: true,
          enabled: !_disabled,
          label: somethingElse,
          child: TextButton.icon(
            key: const ValueKey<String>('ai_v3_clarification_custom'),
            onPressed: _disabled ? null : _showCustomField,
            style: _optionStyle(),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: Text(
              somethingElse,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (_showCustomResponse) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey<String>('ai_v3_clarification_custom_field'),
            controller: _customController,
            focusNode: _customFocusNode,
            enabled: !_disabled,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(_customController.text),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 13.5,
            ),
            decoration: InputDecoration(
              hintText: describeResponse,
              hintStyle: const TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white54,
                fontSize: 13.5,
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.12),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: Semantics(
                button: true,
                enabled: !_disabled,
                label: sendResponse,
                child: IconButton(
                  key: const ValueKey<String>(
                    'ai_v3_clarification_custom_send',
                  ),
                  tooltip: sendResponse,
                  onPressed: _disabled
                      ? null
                      : () => _submit(_customController.text),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                  color: const Color(0xFFF4F4F4),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey<String>('ai_v3_clarification_cancel'),
            onPressed: _disabled ? null : widget.onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              disabledForegroundColor: Colors.white30,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              cancel,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
