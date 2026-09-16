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
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (dialogContext) {
      return MixroomShellDialog(
        maxWidth: 380,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Icon(icon, color: const Color(0xFFF4F4F4), size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color(0xFFF4F4F4),
                      fontSize: 18,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 13.5,
                height: 1.36,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 118,
                child: MixroomShellDialogButton(
                  label: buttonLabel,
                  accent: true,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ],
        ),
      );
    },
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
      return MixroomShellDialog(
        maxWidth: 390,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 19),
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
                      height: 1.18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              L10n.translate(context, message),
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.36,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: MixroomShellDialogButton(
                    label: L10n.translate(context, secondaryLabel),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MixroomShellDialogButton(
                    label: L10n.translate(context, primaryLabel),
                    accent: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  if (action == true) {
    onUpgrade?.call();
  }
}

Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'No',
  IconData icon = Icons.graphic_eq_rounded,
}) async {
  if (!context.mounted) return false;
  final action = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (dialogContext) {
      return MixroomShellDialog(
        maxWidth: 390,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 19),
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
                      height: 1.18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              L10n.translate(context, message),
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.36,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: MixroomShellDialogButton(
                    label: L10n.translate(context, cancelLabel),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MixroomShellDialogButton(
                    label: L10n.translate(context, confirmLabel),
                    accent: true,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return action == true;
}
