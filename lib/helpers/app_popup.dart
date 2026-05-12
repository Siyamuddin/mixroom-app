import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';

enum AppPopupTone { info, success, warning, error }

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppPopupTone tone = AppPopupTone.info,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final colors = Theme.of(context).colorScheme;
  final localizedMessage = L10n.translate(context, message);

  IconData icon;
  Color stripe;
  switch (tone) {
    case AppPopupTone.success:
      icon = Icons.check_circle_outline;
      stripe = Colors.greenAccent.shade400;
      break;
    case AppPopupTone.warning:
      icon = Icons.warning_amber_rounded;
      stripe = Colors.amber.shade300;
      break;
    case AppPopupTone.error:
      icon = Icons.error_outline;
      stripe = Colors.redAccent.shade200;
      break;
    case AppPopupTone.info:
      icon = Icons.info_outline;
      stripe = colors.primary;
      break;
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color.fromRGBO(50, 58, 70, 0.96),
      elevation: 0,
      showCloseIcon: true,
      closeIconColor: const Color(0xFFF4F4F4),
      margin: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        mixroomShellBottomPadding(context) + 16,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      duration: duration,
      content: Row(
        children: [
          Icon(icon, size: 18, color: stripe),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              localizedMessage,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Color(0xFFF4F4F4),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
                letterSpacing: -0.05,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAppMessageDialog({
  required BuildContext context,
  required String title,
  required String message,
  String buttonLabel = 'OK',
  IconData icon = Icons.info_outline,
}) {
  final colors = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(buttonLabel),
        ),
      ],
    ),
  );
}

Future<void> showAppUpgradeDialog({
  required BuildContext context,
  required String title,
  required String message,
  String primaryLabel = 'View plans',
  String secondaryLabel = 'Not now',
  IconData icon = Icons.lock_outline_rounded,
  VoidCallback? onUpgrade,
}) async {
  if (!context.mounted) return;
  final action = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) {
      return AlertDialog(
        backgroundColor: const Color(0xFF5F666D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
        actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.11),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                L10n.translate(context, title),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          L10n.translate(context, message),
          style: TextStyle(
            fontFamily: 'Pretendard',
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              L10n.translate(context, secondaryLabel),
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF258AE6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(L10n.translate(context, primaryLabel)),
          ),
        ],
      );
    },
  );
  if (action == true) {
    onUpgrade?.call();
  }
}
