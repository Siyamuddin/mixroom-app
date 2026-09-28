import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String editor;

  setUpAll(() {
    editor = File('lib/screens/audio_editor.dart').readAsStringSync();
  });

  test('thinking keeps both chat composers editable and focusable', () {
    expect(
      RegExp(r'readOnly: _dawTutorialChatPromptLocked,').allMatches(editor),
      hasLength(2),
    );
    expect(
      editor,
      isNot(contains('readOnly: _dawTutorialChatPromptLocked || _isThinking')),
    );
    expect(editor, contains('readOnly: widget.readOnly,'));
    expect(
      editor,
      isNot(
        contains(
          'widget.readOnly ||\n'
          '                                                    widget.isThinking',
        ),
      ),
    );

    final inlineTapStart = editor.indexOf('onTapBar: () {');
    final inlineTapEnd = editor.indexOf('onSubmit: () async {', inlineTapStart);
    expect(inlineTapStart, greaterThanOrEqualTo(0));
    expect(inlineTapEnd, greaterThan(inlineTapStart));
    final inlineTap = editor.substring(inlineTapStart, inlineTapEnd);
    expect(inlineTap, isNot(contains('if (_isThinking) return;')));
    expect(inlineTap, contains('_chatInputActive = Platform.isMacOS;'));

    final bottomTapStart = editor.indexOf(
      'void _handleBottomChatBarTap({bool trackUiClick = true})',
    );
    final bottomTapEnd = editor.indexOf(
      '\n  Future<void> _submitBottomChatPrompt()',
      bottomTapStart,
    );
    expect(bottomTapStart, greaterThanOrEqualTo(0));
    expect(bottomTapEnd, greaterThan(bottomTapStart));
    final bottomTap = editor.substring(bottomTapStart, bottomTapEnd);
    expect(bottomTap, isNot(contains('if (_isThinking) return;')));
    expect(bottomTap, contains('_chatInputActive = Platform.isMacOS;'));
  });

  test('thinking still blocks a second submission and exposes Stop', () {
    expect(
      RegExp(
        r'textInputAction:\s+widget\.isThinking\s+'
        r'\? TextInputAction\.none\s+: TextInputAction\.send',
      ).hasMatch(editor),
      isTrue,
    );
    expect(
      RegExp(
        r'onSubmitted: widget\.isThinking\s+'
        r'\? null\s+: \(_\) => widget\.onSubmit\(\)',
      ).hasMatch(editor),
      isTrue,
    );
    expect(
      RegExp(
        r'onTap: sendEnabled\s+\? \(widget\.isThinking\s+'
        r'\? widget\s+\.onStop\s+: widget\s+\.onSubmit\)',
      ).hasMatch(editor),
      isTrue,
    );

    final submitStart = editor.indexOf(
      'Future<bool> _submitChatPrompt(String userText) async {',
    );
    expect(submitStart, greaterThanOrEqualTo(0));
    final submitGuard = editor.substring(submitStart, submitStart + 1000);
    expect(submitGuard, contains('if (_isThinking) {'));
  });

  test('finishing or stopping a request does not erase a typed draft', () {
    final endStart = editor.indexOf('void _endChatFlow(int flowId)');
    final stopStart = editor.indexOf('void _stopActiveChatFlow()', endStart);
    final stopEnd = editor.indexOf(
      '\n  void _resolveAiV3Clarification',
      stopStart,
    );
    expect(endStart, greaterThanOrEqualTo(0));
    expect(stopStart, greaterThan(endStart));
    expect(stopEnd, greaterThan(stopStart));

    final lifecycle = editor.substring(endStart, stopEnd);
    expect(lifecycle, isNot(contains('_chatTextController.clear()')));
    expect(lifecycle, isNot(contains('_chatTextController.text =')));
  });
}
