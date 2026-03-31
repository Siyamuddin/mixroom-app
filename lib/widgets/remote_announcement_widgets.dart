import 'dart:io';

import 'package:flutter/material.dart';

import '../helpers/remote_announcement_manager.dart';
import 'app_shell_figma.dart';

class RemoteAnnouncementBanner extends StatelessWidget {
  const RemoteAnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onPrimaryTap,
    required this.onDismissTap,
  });

  final RemoteAnnouncement announcement;
  final VoidCallback onPrimaryTap;
  final VoidCallback onDismissTap;

  @override
  Widget build(BuildContext context) {
    final tone = _announcementTone(announcement.style);
    return MixroomShellSurface(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      color: tone.surfaceColor,
      strong: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnnouncementLeading(
            announcement: announcement,
            size: 46,
            fallbackIcon: tone.icon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tone.badgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Announcement',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      color: tone.badgeTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  announcement.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                  ),
                ),
                if (announcement.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    announcement.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      color: Color.fromRGBO(244, 244, 244, 0.80),
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: onPrimaryTap,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: tone.actionColor,
                      ),
                      child: Text(
                        announcement.primaryButtonLabel,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismissTap,
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
            icon: const Icon(
              Icons.close_rounded,
              color: Color.fromRGBO(244, 244, 244, 0.76),
            ),
          ),
        ],
      ),
    );
  }
}

class RemoteAnnouncementDialog extends StatelessWidget {
  const RemoteAnnouncementDialog({
    super.key,
    required this.announcement,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final RemoteAnnouncement announcement;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final tone = _announcementTone(announcement.style);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: MixroomShellSurface(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          color: tone.surfaceColor,
          strong: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: onSecondaryPressed,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color.fromRGBO(244, 244, 244, 0.74),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _AnnouncementLeading(
                announcement: announcement,
                size: 96,
                fallbackIcon: tone.icon,
              ),
              const SizedBox(height: 18),
              Text(
                announcement.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                ),
              ),
              if (announcement.body.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  announcement.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color.fromRGBO(244, 244, 244, 0.80),
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: onPrimaryPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: tone.actionColor,
                  foregroundColor: const Color(0xFF07131E),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(announcement.primaryButtonLabel),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onSecondaryPressed,
                child: Text(
                  announcement.secondaryButtonLabel,
                  style: const TextStyle(
                      color: Color.fromRGBO(244, 244, 244, 0.72)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementLeading extends StatelessWidget {
  const _AnnouncementLeading({
    required this.announcement,
    required this.size,
    required this.fallbackIcon,
  });

  final RemoteAnnouncement announcement;
  final double size;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.26);
    if (announcement.hasMedia) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(announcement.mediaReference),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _FallbackAnnouncementArt(
            size: size,
            icon: fallbackIcon,
          ),
        ),
      );
    }
    return _FallbackAnnouncementArt(size: size, icon: fallbackIcon);
  }
}

class _FallbackAnnouncementArt extends StatelessWidget {
  const _FallbackAnnouncementArt({
    required this.size,
    required this.icon,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.fromRGBO(92, 162, 224, 0.88),
            Color.fromRGBO(18, 86, 138, 0.92),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: size * 0.42),
    );
  }
}

class _AnnouncementTone {
  const _AnnouncementTone({
    required this.surfaceColor,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.actionColor,
    required this.icon,
  });

  final Color surfaceColor;
  final Color badgeColor;
  final Color badgeTextColor;
  final Color actionColor;
  final IconData icon;
}

_AnnouncementTone _announcementTone(String style) {
  switch (style) {
    case 'success':
      return const _AnnouncementTone(
        surfaceColor: Color.fromRGBO(95, 160, 113, 0.28),
        badgeColor: Color.fromRGBO(203, 247, 213, 0.18),
        badgeTextColor: Color(0xFFD9FFE3),
        actionColor: Color(0xFF91F1A7),
        icon: Icons.check_circle_outline_rounded,
      );
    case 'warning':
      return const _AnnouncementTone(
        surfaceColor: Color.fromRGBO(181, 131, 44, 0.30),
        badgeColor: Color.fromRGBO(255, 219, 153, 0.18),
        badgeTextColor: Color(0xFFFFE2AE),
        actionColor: Color(0xFFFFD066),
        icon: Icons.campaign_outlined,
      );
    case 'critical':
      return const _AnnouncementTone(
        surfaceColor: Color.fromRGBO(171, 71, 71, 0.34),
        badgeColor: Color.fromRGBO(255, 204, 204, 0.18),
        badgeTextColor: Color(0xFFFFD5D5),
        actionColor: Color(0xFFFF8B8B),
        icon: Icons.priority_high_rounded,
      );
    default:
      return const _AnnouncementTone(
        surfaceColor: Color.fromRGBO(151, 184, 216, 0.28),
        badgeColor: Color.fromRGBO(213, 234, 255, 0.18),
        badgeTextColor: Color(0xFFDDEEFF),
        actionColor: Color(0xFF7BC3FF),
        icon: Icons.campaign_outlined,
      );
  }
}
