import 'package:flutter/material.dart';
import 'dart:ui';

import '../models/app_update_policy.dart';
import 'app_shell_figma.dart';

class SoftUpdateDialog extends StatelessWidget {
  const SoftUpdateDialog({
    super.key,
    required this.decision,
    required this.onUpdatePressed,
    required this.onLaterPressed,
  });

  final AppUpdateDecision decision;
  final VoidCallback onUpdatePressed;
  final VoidCallback onLaterPressed;

  @override
  Widget build(BuildContext context) {
    final isForce = decision.type == AppUpdatePromptType.force;
    final accentColor =
        isForce ? const Color(0xFFFFD48A) : const Color(0xFF76AADC);
    final accentTextColor =
        isForce ? const Color(0xFF271300) : const Color(0xFF07131E);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    decoration: mixroomShellSurfaceDecoration(
                      radius: 28,
                      color: const Color.fromRGBO(244, 244, 244, 0.16),
                      strong: true,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            accentColor.withValues(alpha: isForce ? 0.24 : 0.20),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isForce ? 'Update Required' : 'Update Available',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: accentColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isForce
                        ? 'Keep Mixroom up to date.'
                        : 'A newer Mixroom is ready.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFFF4F4F4),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.12,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isForce
                        ? 'A newer version of Mixroom is required to keep using the app.'
                        : 'Update for the latest fixes, improvements, and AI reliability updates.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color.fromRGBO(244, 244, 244, 0.80),
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _VersionPill(
                          label: 'Current',
                          value: decision.currentVersion,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _VersionPill(
                          label: 'Latest',
                          value: decision.latestVersion,
                          emphasize: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: onUpdatePressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: accentTextColor,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Update now'),
                  ),
                  if (!isForce) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: onLaterPressed,
                      style: TextButton.styleFrom(
                        foregroundColor:
                            const Color.fromRGBO(244, 244, 244, 0.72),
                        textStyle: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Later'),
                    ),
                  ],
                      ],
                    ),
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

class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: emphasize
            ? const Color.fromRGBO(118, 170, 220, 0.18)
            : const Color.fromRGBO(244, 244, 244, 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: emphasize ? 0.14 : 0.10),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: emphasize
                  ? const Color(0xFFBEE0FF)
                  : const Color(0xFFF4F4F4),
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
