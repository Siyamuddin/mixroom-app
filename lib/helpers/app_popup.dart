import 'package:flutter/material.dart';
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
      backgroundColor: const Color.fromRGBO(70, 80, 95, 0.86),
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
              message,
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
