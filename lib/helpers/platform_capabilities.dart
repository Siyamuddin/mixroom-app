import 'package:flutter/foundation.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

class PlatformCapabilities {
  final bool isDesktop;
  final bool isMobile;
  final bool supportsVideoProjects;
  final bool lockPortraitOrientation;
  final bool supportsFfmpegPostProcessing;
  final bool externalPluginHosting;
  final List<String> supportedPluginFormats;
  final bool nativePluginEditor;

  const PlatformCapabilities({
    required this.isDesktop,
    required this.isMobile,
    required this.supportsVideoProjects,
    required this.lockPortraitOrientation,
    required this.supportsFfmpegPostProcessing,
    required this.externalPluginHosting,
    required this.supportedPluginFormats,
    required this.nativePluginEditor,
  });

  bool get isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get desktopNativeWavOnlyExport =>
      isDesktop && !supportsFfmpegPostProcessing;

  bool get supportsExternalPluginAffordances =>
      externalPluginHosting || !isDesktop;

  PlatformCapabilities copyWith({
    bool? isDesktop,
    bool? isMobile,
    bool? supportsVideoProjects,
    bool? lockPortraitOrientation,
    bool? supportsFfmpegPostProcessing,
    bool? externalPluginHosting,
    List<String>? supportedPluginFormats,
    bool? nativePluginEditor,
  }) {
    return PlatformCapabilities(
      isDesktop: isDesktop ?? this.isDesktop,
      isMobile: isMobile ?? this.isMobile,
      supportsVideoProjects:
          supportsVideoProjects ?? this.supportsVideoProjects,
      lockPortraitOrientation:
          lockPortraitOrientation ?? this.lockPortraitOrientation,
      supportsFfmpegPostProcessing:
          supportsFfmpegPostProcessing ?? this.supportsFfmpegPostProcessing,
      externalPluginHosting:
          externalPluginHosting ?? this.externalPluginHosting,
      supportedPluginFormats:
          supportedPluginFormats ?? this.supportedPluginFormats,
      nativePluginEditor: nativePluginEditor ?? this.nativePluginEditor,
    );
  }

  static PlatformCapabilities _cached = _fallbackForCurrentPlatform();

  static PlatformCapabilities get current => _cached;

  static PlatformCapabilities _fallbackForCurrentPlatform() {
    if (kIsWeb) {
      return const PlatformCapabilities(
        isDesktop: false,
        isMobile: false,
        supportsVideoProjects: false,
        lockPortraitOrientation: false,
        supportsFfmpegPostProcessing: false,
        externalPluginHosting: false,
        supportedPluginFormats: <String>[],
        nativePluginEditor: false,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const PlatformCapabilities(
          isDesktop: false,
          isMobile: true,
          supportsVideoProjects: true,
          lockPortraitOrientation: true,
          supportsFfmpegPostProcessing: true,
          externalPluginHosting: false,
          supportedPluginFormats: <String>[],
          nativePluginEditor: false,
        );
      case TargetPlatform.iOS:
        return const PlatformCapabilities(
          isDesktop: false,
          isMobile: true,
          supportsVideoProjects: true,
          lockPortraitOrientation: true,
          supportsFfmpegPostProcessing: true,
          externalPluginHosting: false,
          supportedPluginFormats: <String>['AUv3'],
          nativePluginEditor: false,
        );
      case TargetPlatform.macOS:
        return const PlatformCapabilities(
          isDesktop: true,
          isMobile: false,
          supportsVideoProjects: false,
          lockPortraitOrientation: false,
          supportsFfmpegPostProcessing: true,
          externalPluginHosting: true,
          supportedPluginFormats: <String>['AU', 'VST3'],
          nativePluginEditor: false,
        );
      case TargetPlatform.windows:
        return const PlatformCapabilities(
          isDesktop: true,
          isMobile: false,
          supportsVideoProjects: false,
          lockPortraitOrientation: false,
          supportsFfmpegPostProcessing: false,
          externalPluginHosting: true,
          supportedPluginFormats: <String>['VST3'],
          nativePluginEditor: false,
        );
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const PlatformCapabilities(
          isDesktop: true,
          isMobile: false,
          supportsVideoProjects: false,
          lockPortraitOrientation: false,
          supportsFfmpegPostProcessing: true,
          externalPluginHosting: false,
          supportedPluginFormats: <String>[],
          nativePluginEditor: false,
        );
    }
  }

  static Future<PlatformCapabilities> refresh() async {
    final fallback = _fallbackForCurrentPlatform();
    final engineCaps = await JuceAudioEngine.getEngineCapabilities();

    final merged = fallback.copyWith(
      externalPluginHosting: engineCaps.externalPluginHosting,
      supportedPluginFormats: engineCaps.supportedPluginFormats,
      nativePluginEditor: engineCaps.nativePluginEditor,
    );

    _cached = merged;
    return merged;
  }
}
