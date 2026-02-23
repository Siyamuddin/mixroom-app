import 'package:flutter/material.dart';

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
      duration: duration,
      content: Row(
        children: [
          Icon(icon, size: 18, color: stripe),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
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
