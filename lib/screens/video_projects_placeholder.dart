import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';

class VideoProjectsPlaceholderScreen extends StatelessWidget {
  const VideoProjectsPlaceholderScreen({
    super.key,
    this.showAppBar = false,
  });

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final content = const VideoProjectsPlaceholderView();

    if (!showAppBar) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C1A32),
        body: content,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C1A32),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1A32),
        foregroundColor: Colors.white,
        title: Text(L10n.translate(context, 'Video Projects')),
      ),
      body: content,
    );
  }
}

class VideoProjectsPlaceholderView extends StatelessWidget {
  const VideoProjectsPlaceholderView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
          decoration: BoxDecoration(
            color: const Color(0xFF142845),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.video_library_rounded,
                color: Colors.white70,
                size: 52,
              ),
              const SizedBox(height: 14),
              Text(
                L10n.translate(context, 'Video Projects'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.translate(context, 'Coming soon'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
