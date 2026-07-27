class AiV3AudioFacts {
  const AiV3AudioFacts({
    required this.mixProcessingSupported,
    required this.hasUsableSignal,
    required this.analysisAvailable,
    required this.referenceSuitable,
  });

  factory AiV3AudioFacts.fromAnalysis({
    required bool mixProcessingSupported,
    required bool hasAudio,
    required double approxRms,
    required Map<Object?, Object?> audioStatistics,
  }) {
    final hasUsableSignal = hasAudio && approxRms.isFinite && approxRms > 0.001;
    final analysisAvailable = audioStatistics.isNotEmpty;
    return AiV3AudioFacts(
      mixProcessingSupported: mixProcessingSupported,
      hasUsableSignal: hasUsableSignal,
      analysisAvailable: analysisAvailable,
      referenceSuitable: hasUsableSignal && analysisAvailable,
    );
  }

  final bool mixProcessingSupported;
  final bool hasUsableSignal;
  final bool analysisAvailable;
  final bool referenceSuitable;

  Map<String, bool> toJson() => <String, bool>{
        'mix_processing_supported': mixProcessingSupported,
        'has_usable_signal': hasUsableSignal,
        'analysis_available': analysisAvailable,
        'reference_suitable': referenceSuitable,
      };
}
