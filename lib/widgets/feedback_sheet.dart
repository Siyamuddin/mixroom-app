import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/feedback_models.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';

Future<FeedbackDraft?> showFeedbackSheet(
  BuildContext context, {
  required FeedbackSource source,
}) {
  return showDialog<FeedbackDraft>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.62),
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
        const SnackBar(
            content: Text('Please enter your feedback or bug report first.')),
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
    final mediaQuery = MediaQuery.of(context);
    final remaining = FeedbackTextSanitizer.maxChars -
        FeedbackTextSanitizer.sanitize(
          _messageController.text,
          maxCharacters: FeedbackTextSanitizer.maxChars,
        ).length;
    final maxWidth = math.min(
      mediaQuery.size.width - 24,
      _showDawOptions ? 460.0 : 440.0,
    );
    final maxHeight = math.min(
      mediaQuery.size.height * (_showDawOptions ? 0.82 : 0.88),
      _showDawOptions ? 700.0 : 700.0,
    );
    final keyboardInset = math.min(
      mediaQuery.viewInsets.bottom,
      mediaQuery.size.height * 0.28,
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + keyboardInset),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: Material(
              color: Colors.transparent,
              child: MixroomShellSurface(
                radius: 32,
                strong: true,
                color: const Color.fromRGBO(24, 34, 48, 0.92),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _messageFocusNode.unfocus(),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              kMixroomShellBrandMarkAsset,
                              width: 54,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              L10n.translate(context, 'Send Feedback'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Color(0xFFF4F4F4),
                                fontSize: 24,
                                fontWeight: FontWeight.w400,
                                height: 30 / 24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _showDawOptions
                                  ? 'Choose feedback or bug report, then describe it. You can also attach current editor context.'
                                  : 'Choose feedback or bug report, then describe it. Account details are attached automatically.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 13,
                                height: 18 / 13,
                              ),
                            ),
                            const SizedBox(height: 22),
                            MixroomShellSegmentedControl<FeedbackCategory>(
                              value: _category,
                              options: const [
                                FeedbackCategory.feedback,
                                FeedbackCategory.bugReport,
                              ],
                              labelBuilder: (category) =>
                                  category == FeedbackCategory.feedback
                                      ? 'Feedback'
                                      : 'Bug Report',
                              onChanged: (next) {
                                HapticFeedback.selectionClick();
                                setState(() => _category = next);
                              },
                            ),
                            const SizedBox(height: 22),
                            MixroomShellSurface(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              color: const Color.fromRGBO(244, 244, 244, 0.10),
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                autofocus: false,
                                minLines: 5,
                                maxLines: 7,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.done,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (_) => _messageFocusNode.unfocus(),
                                onEditingComplete: _messageFocusNode.unfocus,
                                onTapOutside: (_) =>
                                    _messageFocusNode.unfocus(),
                                inputFormatters: <TextInputFormatter>[
                                  LengthLimitingTextInputFormatter(
                                    FeedbackTextSanitizer.maxChars,
                                  ),
                                ],
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color(0xFFF4F4F4),
                                  fontSize: 15,
                                  height: 22 / 15,
                                ),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                  hintText: _category ==
                                          FeedbackCategory.feedback
                                      ? 'Tell us what is working, missing, or would make this better.'
                                      : 'Describe the bug, what you expected, and what happened.',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(alpha: 0.48),
                                    fontSize: 15,
                                    height: 22 / 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '$remaining characters left',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: remaining < 120
                                      ? const Color(0xFFFFC26B)
                                      : Colors.white.withValues(alpha: 0.56),
                                  fontSize: 11,
                                  height: 14 / 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ShellCheckboxRow(
                              value: _allowEmailContact,
                              title: 'Allow Mixroom to respond by email.',
                              subtitle:
                                  'Optional. We may follow up using your account email about this submission.',
                              onChanged: (value) {
                                setState(() => _allowEmailContact = value);
                              },
                            ),
                            if (_showDawOptions) ...[
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Include with this report',
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 16 / 13,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              MixroomShellSurface(
                                radius: 24,
                                padding: EdgeInsets.zero,
                                color:
                                    const Color.fromRGBO(244, 244, 244, 0.10),
                                child: Column(
                                  children: [
                                    _ShellCheckboxRow(
                                      value: _includeDawContext,
                                      title:
                                          'Include AI chat history and project settings.',
                                      subtitle:
                                          'Attach recent assistant messages and current DAW settings.',
                                      padded: true,
                                      onChanged: (value) {
                                        setState(
                                          () => _includeDawContext = value,
                                        );
                                      },
                                    ),
                                    Divider(
                                      height: 1,
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    _ShellCheckboxRow(
                                      value: _includeDawScreenshot,
                                      title: 'Include a DAW screenshot.',
                                      subtitle:
                                          'Mixroom captures the editor view with chat closed.',
                                      padded: true,
                                      onChanged: (value) {
                                        setState(
                                          () => _includeDawScreenshot = value,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: _FeedbackDialogActionButton(
                                    label: 'Cancel',
                                    fillColor: const Color.fromRGBO(
                                        244, 244, 244, 0.18),
                                    onTap: () => Navigator.of(context).pop(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _FeedbackDialogActionButton(
                                    label: 'Submit',
                                    fillColor: const Color.fromRGBO(
                                        244, 244, 244, 0.58),
                                    onTap: _submit,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: MixroomShellRoundButton(
                          size: 42,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellCheckboxRow extends StatelessWidget {
  const _ShellCheckboxRow({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
    this.padded = false,
  });

  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Padding(
        padding: padded
            ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
            : EdgeInsets.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: value
                  ? SvgPicture.asset(
                      kMixroomShellCheckboxCheckedAsset,
                      width: 20,
                      height: 20,
                    )
                  : Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.65),
                          width: 1.4,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFFF4F4F4),
                      fontSize: 15,
                      height: 15 / 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 10,
                      height: 15 / 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackDialogActionButton extends StatelessWidget {
  const _FeedbackDialogActionButton({
    required this.label,
    required this.fillColor,
    required this.onTap,
  });

  final String label;
  final Color fillColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MixroomShellSurface(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        color: fillColor,
        child: SizedBox(
          width: double.infinity,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 22 / 15,
            ),
          ),
        ),
      ),
    );
  }
}
