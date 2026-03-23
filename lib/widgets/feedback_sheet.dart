import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mixroom/models/feedback_models.dart';

Future<FeedbackDraft?> showFeedbackSheet(
  BuildContext context, {
  required FeedbackSource source,
}) {
  return showDialog<FeedbackDraft>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _FeedbackSheet(source: source),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({
    required this.source,
  });

  final FeedbackSource source;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  late final TextEditingController _messageController;
  late final FocusNode _messageFocusNode;
  FeedbackCategory _category = FeedbackCategory.feedback;
  bool _allowEmailContact = false;
  bool _includeDawContext = true;
  bool _includeDawScreenshot = false;

  bool get _showDawOptions => widget.source == FeedbackSource.dawChat;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _messageFocusNode = FocusNode();
    _messageController.addListener(_handleMessageChanged);
    _messageFocusNode.addListener(_handleMessageChanged);
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_handleMessageChanged)
      ..dispose();
    _messageFocusNode
      ..removeListener(_handleMessageChanged)
      ..dispose();
    super.dispose();
  }

  void _handleMessageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _submit() {
    final message = FeedbackTextSanitizer.sanitize(_messageController.text);
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback or bug report first.')),
      );
      return;
    }

    Navigator.of(context).pop(
      FeedbackDraft(
        category: _category,
        message: message,
        allowEmailContact: _allowEmailContact,
        includeDawContext: _showDawOptions && _includeDawContext,
        includeDawScreenshot: _showDawOptions && _includeDawScreenshot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final remaining = FeedbackTextSanitizer.maxChars -
        FeedbackTextSanitizer.sanitize(
          _messageController.text,
          maxCharacters: FeedbackTextSanitizer.maxChars,
        ).length;
    final maxWidth = math.min(mediaQuery.size.width - 24, 560.0);
    final maxHeight = math.min(
      mediaQuery.size.height * 0.88,
      _showDawOptions ? 720.0 : 620.0,
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
            child: Material(
              color: const Color(0xFF131A24),
              elevation: 24,
              shadowColor: Colors.black.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _messageFocusNode.unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Send feedback or report a bug',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose feedback or bug report, then describe it. Account details are attached automatically.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<FeedbackCategory>(
                    multiSelectionEnabled: false,
                    selected: <FeedbackCategory>{_category},
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.resolveWith<Color>(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.white
                            : Colors.white70,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith<Color>(
                        (states) => states.contains(WidgetState.selected)
                            ? const Color(0xFF3E82FF)
                            : Colors.white.withValues(alpha: 0.05),
                      ),
                      side: WidgetStateProperty.all(
                        BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                    ),
                    segments: const <ButtonSegment<FeedbackCategory>>[
                      ButtonSegment<FeedbackCategory>(
                        value: FeedbackCategory.feedback,
                        label: Text('Feedback'),
                        icon: Icon(Icons.forum_outlined),
                      ),
                      ButtonSegment<FeedbackCategory>(
                        value: FeedbackCategory.bugReport,
                        label: Text('Bug report'),
                        icon: Icon(Icons.bug_report_outlined),
                      ),
                    ],
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      HapticFeedback.selectionClick();
                      setState(() => _category = selection.first);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    autofocus: false,
                    minLines: 4,
                    maxLines: 7,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _messageFocusNode.unfocus(),
                    onEditingComplete: _messageFocusNode.unfocus,
                    onTapOutside: (_) => _messageFocusNode.unfocus(),
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(FeedbackTextSanitizer.maxChars),
                    ],
                    decoration: InputDecoration(
                      hintText: _category == FeedbackCategory.feedback
                          ? 'Tell us what is working, missing, or would make this better.'
                          : 'Describe the bug, what you expected, and what happened.',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF6EA6FF)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$remaining characters left',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            remaining < 120 ? const Color(0xFFFFC26B) : Colors.white60,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CompactCheckboxRow(
                    value: _allowEmailContact,
                    title: 'Allow Mixroom to respond by email',
                    subtitle: 'Optional. We may follow up using your account email about this submission.',
                    hasBackground: false,
                    onChanged: (value) {
                      setState(() => _allowEmailContact = value);
                    },
                  ),
                  if (_showDawOptions) ...[
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        children: [
                          _CompactCheckboxRow(
                            value: _includeDawContext,
                            title: 'Include AI chat history and project settings',
                            subtitle: 'Attach recent assistant messages and current DAW settings.',
                            onChanged: (value) {
                              setState(() => _includeDawContext = value);
                            },
                          ),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          _CompactCheckboxRow(
                            value: _includeDawScreenshot,
                            title: 'Include a DAW screenshot',
                            subtitle: 'Mixroom captures the editor view with chat closed.',
                            onChanged: (value) {
                              setState(() => _includeDawScreenshot = value);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3E82FF),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Submit'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactCheckboxRow extends StatelessWidget {
  const _CompactCheckboxRow({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
    this.hasBackground = true,
  });

  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;
  final bool hasBackground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: hasBackground ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(-4, -2),
                child: Checkbox(
                  value: value,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (next) => onChanged(next ?? false),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
