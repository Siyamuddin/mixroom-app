import 'dart:ui';

import 'package:flutter/material.dart';

/// Blocking recovery surface shown while the editor has no usable audio
/// session and has intentionally not restored the project.
class AudioStartupRecoveryCard extends StatelessWidget {
  const AudioStartupRecoveryCard({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.backLabel,
    required this.onRetry,
    required this.onBack,
    this.retryFocusNode,
    this.backFocusNode,
    this.retryInProgress = false,
  });

  static const Key overlayKey = Key('editor_audio_startup_recovery_overlay');
  static const Key retryButtonKey = Key('editor_audio_startup_retry');
  static const Key backButtonKey = Key('editor_audio_startup_back');

  final String title;
  final String message;
  final String retryLabel;
  final String backLabel;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final FocusNode? retryFocusNode;
  final FocusNode? backFocusNode;
  final bool retryInProgress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BlockSemantics(
      child: Stack(
        key: overlayKey,
        children: <Widget>[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0xB8000000)),
          ),
          Positioned.fill(
            child: FocusScope(
              autofocus: true,
              child: SafeArea(
                minimum: const EdgeInsets.all(20),
                child: Center(
                  child: SingleChildScrollView(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      liveRegion: true,
                      label: '$title $message',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxWidth: 440),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(34, 43, 56, 0.97),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                ExcludeSemantics(
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.volume_off_rounded,
                                      color: Color(0xFFF4F4F4),
                                      size: 28,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                ExcludeSemantics(
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: textTheme.titleLarge?.copyWith(
                                      fontFamily: 'Pretendard',
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFF4F4F4),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ExcludeSemantics(
                                  child: Text(
                                    message,
                                    textAlign: TextAlign.center,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontFamily: 'Pretendard',
                                      height: 1.4,
                                      color: const Color(0xFFD5DAE1),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final stackButtons =
                                        constraints.maxWidth < 300;
                                    final retry = _RecoveryButton(
                                      key: retryButtonKey,
                                      label: retryLabel,
                                      primary: true,
                                      inProgress: retryInProgress,
                                      focusNode: retryFocusNode,
                                      autofocus: true,
                                      onPressed: retryInProgress
                                          ? null
                                          : onRetry,
                                    );
                                    final back = _RecoveryButton(
                                      key: backButtonKey,
                                      label: backLabel,
                                      focusNode: backFocusNode,
                                      onPressed: retryInProgress
                                          ? null
                                          : onBack,
                                    );
                                    if (stackButtons) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: <Widget>[
                                          retry,
                                          const SizedBox(height: 10),
                                          back,
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: <Widget>[
                                        Expanded(child: back),
                                        const SizedBox(width: 12),
                                        Expanded(child: retry),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryButton extends StatelessWidget {
  const _RecoveryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.inProgress = false,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool inProgress;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final foreground = const Color(0xFFF4F4F4);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      child: inProgress
          ? const SizedBox(
              key: ValueKey<String>('progress'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFFF4F4F4),
              ),
            )
          : Text(
              label,
              key: const ValueKey<String>('label'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    final style = primary
        ? FilledButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: const Color(0xFF147CC1),
            disabledForegroundColor: foreground.withValues(alpha: 0.7),
            disabledBackgroundColor: const Color(
              0xFF147CC1,
            ).withValues(alpha: 0.55),
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: shape,
          )
        : OutlinedButton.styleFrom(
            foregroundColor: foreground,
            disabledForegroundColor: foreground.withValues(alpha: 0.5),
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
            shape: shape,
          );
    return primary
        ? FilledButton(
            focusNode: focusNode,
            autofocus: autofocus,
            onPressed: onPressed,
            style: style,
            child: child,
          )
        : OutlinedButton(
            focusNode: focusNode,
            autofocus: autofocus,
            onPressed: onPressed,
            style: style,
            child: child,
          );
  }
}
