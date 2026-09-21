import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/account_glass_ui.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';

class MixroomProfileAvatar extends StatelessWidget {
  const MixroomProfileAvatar({
    super.key,
    required this.size,
    this.avatarUrl,
    this.initials,
    this.emptyChild,
    this.isBusy = false,
    this.onTap,
    this.showCameraBadge = true,
    this.borderColor,
    this.borderWidth = 0.8,
    this.backgroundColor,
    this.initialsStyle,
  });

  final double size;
  final String? avatarUrl;
  final String? initials;
  final Widget? emptyChild;
  final bool isBusy;
  final VoidCallback? onTap;
  final bool showCameraBadge;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;
  final TextStyle? initialsStyle;

  bool get _hasPhoto {
    final url = avatarUrl?.trim() ?? '';
    return url.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final badgeSize = (size * 0.28).clamp(22.0, 30.0);
    final semanticLabel = L10n.translate(
      context,
      _hasPhoto ? 'Profile photo, double tap to view' : 'Add profile photo',
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isBusy ? null : onTap,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        backgroundColor ?? Colors.white.withValues(alpha: 0.16),
                    border: Border.all(
                      color:
                          borderColor ?? Colors.white.withValues(alpha: 0.42),
                      width: borderWidth,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(child: _buildFace()),
                ),
              ),
            ),
            if (isBusy)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFFF4F4F4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (showCameraBadge && !_hasPhoto && !isBusy)
              Positioned(
                right: -2,
                bottom: -2,
                child: IgnorePointer(
                  child: Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      color: kAccountGlassBlue,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFF4F4F4),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.32),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.photo_camera_rounded,
                      size: badgeSize * 0.52,
                      color: const Color(0xFFF4F4F4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFace() {
    if (_hasPhoto) {
      return Image.network(
        avatarUrl!.trim(),
        fit: BoxFit.cover,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => _buildEmpty(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return ColoredBox(
            color: Colors.black.withValues(alpha: 0.18),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFF4F4F4),
                ),
              ),
            ),
          );
        },
      );
    }
    return _buildEmpty();
  }

  Widget _buildEmpty() {
    if (emptyChild != null) return emptyChild!;
    final label = (initials ?? 'M').trim();
    return Center(
      child: Text(
        label.isEmpty ? 'M' : label,
        style:
            initialsStyle ??
            TextStyle(
              color: Colors.white,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

Future<void> showMixroomProfileAvatarViewer({
  required BuildContext context,
  required String avatarUrl,
  required VoidCallback onChangePhoto,
  required VoidCallback onRemovePhoto,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: L10n.translate(context, 'Close'),
    barrierColor: Colors.black.withValues(alpha: 0.78),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final shortest = MediaQuery.sizeOf(dialogContext).shortestSide;
      final photoSize = (shortest * 0.72).clamp(220.0, 360.0);
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 10,
                right: 14,
                child: MixroomShellRoundButton(
                  size: 42,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: Color(0xFFF4F4F4),
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: photoSize,
                        height: photoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.42),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.46),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            width: photoSize,
                            height: photoSize,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) {
                              return ColoredBox(
                                color: const Color(0xFF3E4244),
                                child: Icon(
                                  Icons.person_rounded,
                                  size: photoSize * 0.42,
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ViewerActionButton(
                                label: L10n.translate(
                                  dialogContext,
                                  'Change photo',
                                ),
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  onChangePhoto();
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ViewerActionButton(
                                label: L10n.translate(dialogContext, 'Remove'),
                                danger: true,
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  onRemovePhoto();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ViewerActionButton extends StatelessWidget {
  const _ViewerActionButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: accountGlassDecoration(danger: danger, strong: true),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: danger ? kAccountGlassDanger : kAccountGlassText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
