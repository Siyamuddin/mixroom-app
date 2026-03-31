class AnalyticsEvent {
  const AnalyticsEvent(
    this.name, {
    this.properties = const <String, Object?>{},
  });

  final String name;
  final Map<String, Object?> properties;
}

class AnalyticsScreenNames {
  const AnalyticsScreenNames._();

  static const String home = 'home';
  static const String projectsList = 'projects_list';
  static const String projectEditor = 'project_editor';
  static const String upload = 'upload';
  static const String export = 'export';
  static const String aiAssistant = 'ai_assistant';
  static const String paywall = 'paywall';
  static const String settings = 'settings';
}

class AnalyticsEvents {
  const AnalyticsEvents._();

  static const String appOpenedName = 'app_opened';
  static const String sessionStartedName = 'session_started';
  static const String sessionEndedName = 'session_ended';
  static const String userSignedUpName = 'user_signed_up';
  static const String userLoggedInName = 'user_logged_in';
  static const String userLoggedOutName = 'user_logged_out';
  static const String projectCreatedName = 'project_created';
  static const String firstProjectCreatedName = 'first_project_created';
  static const String projectOpenedName = 'project_opened';
  static const String exportStartedName = 'export_started';
  static const String exportCompletedName = 'export_completed';
  static const String exportFailedName = 'export_failed';
  static const String aiPromptSubmittedName = 'ai_prompt_submitted';
  static const String aiResponseCompletedName = 'ai_response_completed';
  static const String aiResponseFailedName = 'ai_response_failed';
  static const String aiPromptCycleCompletedName = 'ai_prompt_cycle_completed';
  static const String aiPromptCycleFailedName = 'ai_prompt_cycle_failed';
  static const String aiMagnitudeModelUpdateName = 'ai_magnitude_model_update';
  static const String welcomeOnboardingShownName = 'welcome_onboarding_shown';
  static const String welcomeOnboardingCompletedName =
      'welcome_onboarding_completed';
  static const String remoteAnnouncementUpdateName =
      'remote_announcement_update';
  static const String remoteAnnouncementShownName = 'remote_announcement_shown';
  static const String remoteAnnouncementInteractedName =
      'remote_announcement_interacted';
  static const String aiToolCalledName = 'ai_tool_called';
  static const String aiFeatureViewedName = 'ai_feature_viewed';
  static const String subscriptionStartedName = 'subscription_started';
  static const String purchaseFailedName = 'purchase_failed';
  static const String aiUsageLimitHitName = 'ai_usage_limit_hit';
  static const String uploadFailedName = 'upload_failed';

  static AnalyticsEvent appOpened({
    required String sessionId,
    required String launchSource,
  }) {
    return AnalyticsEvent(
      appOpenedName,
      properties: _compact(<String, Object?>{
        'session_id': sessionId,
        'launch_source': launchSource,
      }),
    );
  }

  static AnalyticsEvent sessionStarted({
    required String sessionId,
  }) {
    return AnalyticsEvent(
      sessionStartedName,
      properties: _compact(<String, Object?>{
        'session_id': sessionId,
      }),
    );
  }

  static AnalyticsEvent sessionEnded({
    required String sessionId,
    required int durationMs,
  }) {
    return AnalyticsEvent(
      sessionEndedName,
      properties: _compact(<String, Object?>{
        'session_id': sessionId,
        'duration_ms': durationMs,
      }),
    );
  }

  static AnalyticsEvent userSignedUp({
    required String signupMethod,
    String? referralSource,
  }) {
    return AnalyticsEvent(
      userSignedUpName,
      properties: _compact(<String, Object?>{
        'signup_method': signupMethod,
        'referral_source': referralSource,
      }),
    );
  }

  static AnalyticsEvent userLoggedIn({
    required String loginMethod,
  }) {
    return AnalyticsEvent(
      userLoggedInName,
      properties: _compact(<String, Object?>{
        'login_method': loginMethod,
      }),
    );
  }

  static AnalyticsEvent userLoggedOut() {
    return const AnalyticsEvent(userLoggedOutName);
  }

  static AnalyticsEvent projectCreated({
    required String projectId,
    required int initialTrackCount,
  }) {
    return AnalyticsEvent(
      projectCreatedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'initial_track_count': initialTrackCount,
      }),
    );
  }

  static AnalyticsEvent firstProjectCreated({
    required String projectId,
  }) {
    return AnalyticsEvent(
      firstProjectCreatedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
      }),
    );
  }

  static AnalyticsEvent projectOpened({
    required String projectId,
    required int trackCount,
  }) {
    return AnalyticsEvent(
      projectOpenedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'track_count': trackCount,
      }),
    );
  }

  static AnalyticsEvent uploadFailed({
    required int fileSize,
    required String errorCode,
  }) {
    return AnalyticsEvent(
      uploadFailedName,
      properties: _compact(<String, Object?>{
        'file_size': fileSize,
        'error_code': errorCode,
      }),
    );
  }

  static AnalyticsEvent exportStarted({
    required String projectId,
    required String exportType,
    required int trackCount,
  }) {
    return AnalyticsEvent(
      exportStartedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'export_type': exportType,
        'track_count': trackCount,
      }),
    );
  }

  static AnalyticsEvent exportCompleted({
    required String projectId,
    required String exportType,
    required int durationMs,
    required int fileSize,
  }) {
    return AnalyticsEvent(
      exportCompletedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'export_type': exportType,
        'duration_ms': durationMs,
        'file_size': fileSize,
        'success': true,
      }),
    );
  }

  static AnalyticsEvent exportFailed({
    required String projectId,
    required String errorCode,
    String? errorMessage,
  }) {
    return AnalyticsEvent(
      exportFailedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'error_code': errorCode,
        'error_message': errorMessage,
        'success': false,
      }),
    );
  }

  static AnalyticsEvent aiFeatureViewed({
    required String featureName,
  }) {
    return AnalyticsEvent(
      aiFeatureViewedName,
      properties: _compact(<String, Object?>{
        'feature_name': featureName,
      }),
    );
  }

  static AnalyticsEvent aiPromptSubmitted({
    required String projectId,
    required String aiFeature,
    String? modelName,
    String? promptTraceId,
    String? runtimeConfigFingerprint,
    bool? hasSystemPromptOverride,
    String? mixMagnitudeModelSource,
    String? mixMagnitudeModelBundleVersion,
    String? mixApplyModelVersion,
    String? mixMagnitudeRegressorVersion,
  }) {
    return AnalyticsEvent(
      aiPromptSubmittedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'model_name': modelName,
        'prompt_trace_id': promptTraceId,
        'runtime_config_fingerprint': runtimeConfigFingerprint,
        'has_system_prompt_override': hasSystemPromptOverride,
        'mix_magnitude_model_source': mixMagnitudeModelSource,
        'mix_magnitude_model_bundle_version': mixMagnitudeModelBundleVersion,
        'mix_apply_model_version': mixApplyModelVersion,
        'mix_magnitude_regressor_version': mixMagnitudeRegressorVersion,
      }),
    );
  }

  static AnalyticsEvent aiResponseCompleted({
    required String projectId,
    required String aiFeature,
    String? modelName,
    String? promptTraceId,
    String? runtimeConfigFingerprint,
    bool? hasSystemPromptOverride,
    int? latencyMs,
    int? tokensPrompt,
    int? tokensCompletion,
    int? tokensTotal,
    int? cachedPromptTokens,
    double? estimatedCostUsd,
  }) {
    return AnalyticsEvent(
      aiResponseCompletedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'model_name': modelName,
        'prompt_trace_id': promptTraceId,
        'runtime_config_fingerprint': runtimeConfigFingerprint,
        'has_system_prompt_override': hasSystemPromptOverride,
        'latency_ms': latencyMs,
        'tokens_prompt': tokensPrompt,
        'tokens_completion': tokensCompletion,
        'tokens_total': tokensTotal,
        'cached_prompt_tokens': cachedPromptTokens,
        'estimated_cost_usd': estimatedCostUsd,
        'success': true,
      }),
    );
  }

  static AnalyticsEvent aiResponseFailed({
    required String projectId,
    required String aiFeature,
    required String errorCode,
    String? promptTraceId,
    String? runtimeConfigFingerprint,
    bool? hasSystemPromptOverride,
  }) {
    return AnalyticsEvent(
      aiResponseFailedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'error_code': errorCode,
        'prompt_trace_id': promptTraceId,
        'runtime_config_fingerprint': runtimeConfigFingerprint,
        'has_system_prompt_override': hasSystemPromptOverride,
        'success': false,
      }),
    );
  }

  static AnalyticsEvent aiPromptCycleCompleted({
    required String projectId,
    required String aiFeature,
    required String promptTraceId,
    String? toolName,
    String? modelName,
    String? runtimeConfigFingerprint,
    bool? hasSystemPromptOverride,
    int? projectStatsMs,
    int? proxyRoundtripMs,
    int? responseParseMs,
    int? mixPlanMs,
    int? mixModelHeuristicMs,
    int? mixModelOnnxMs,
    int? applyMixMs,
    int? promptCycleTotalMs,
    int? openAiApiMs,
    int? providerRoundtripMs,
    int? responseNormalizeMs,
    int? proxyHandlerMsTotal,
    int? tokensPrompt,
    int? tokensCompletion,
    int? tokensTotal,
    int? cachedPromptTokens,
    double? estimatedCostUsd,
    String? mixMagnitudeModelSource,
    String? mixMagnitudeModelBundleVersion,
    String? mixApplyModelVersion,
    String? mixMagnitudeRegressorVersion,
  }) {
    return AnalyticsEvent(
      aiPromptCycleCompletedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'prompt_trace_id': promptTraceId,
        'tool_name': toolName,
        'model_name': modelName,
        'runtime_config_fingerprint': runtimeConfigFingerprint,
        'has_system_prompt_override': hasSystemPromptOverride,
        'project_stats_ms': projectStatsMs,
        'proxy_roundtrip_ms': proxyRoundtripMs,
        'response_parse_ms': responseParseMs,
        'mix_plan_ms': mixPlanMs,
        'mix_model_heuristic_ms': mixModelHeuristicMs,
        'mix_model_onnx_ms': mixModelOnnxMs,
        'apply_mix_ms': applyMixMs,
        'prompt_cycle_total_ms': promptCycleTotalMs,
        'openai_api_ms': openAiApiMs,
        'provider_roundtrip_ms': providerRoundtripMs,
        'response_normalize_ms': responseNormalizeMs,
        'proxy_handler_ms_total': proxyHandlerMsTotal,
        'tokens_prompt': tokensPrompt,
        'tokens_completion': tokensCompletion,
        'tokens_total': tokensTotal,
        'cached_prompt_tokens': cachedPromptTokens,
        'estimated_cost_usd': estimatedCostUsd,
        'mix_magnitude_model_source': mixMagnitudeModelSource,
        'mix_magnitude_model_bundle_version': mixMagnitudeModelBundleVersion,
        'mix_apply_model_version': mixApplyModelVersion,
        'mix_magnitude_regressor_version': mixMagnitudeRegressorVersion,
        'success': true,
      }),
    );
  }

  static AnalyticsEvent aiPromptCycleFailed({
    required String projectId,
    required String aiFeature,
    required String promptTraceId,
    required String errorCode,
    String? toolName,
    String? modelName,
    String? runtimeConfigFingerprint,
    bool? hasSystemPromptOverride,
    int? projectStatsMs,
    int? proxyRoundtripMs,
    int? responseParseMs,
    int? mixPlanMs,
    int? mixModelHeuristicMs,
    int? mixModelOnnxMs,
    int? applyMixMs,
    int? promptCycleTotalMs,
    int? openAiApiMs,
    int? providerRoundtripMs,
    int? responseNormalizeMs,
    int? proxyHandlerMsTotal,
    int? tokensPrompt,
    int? tokensCompletion,
    int? tokensTotal,
    int? cachedPromptTokens,
    double? estimatedCostUsd,
    String? mixMagnitudeModelSource,
    String? mixMagnitudeModelBundleVersion,
    String? mixApplyModelVersion,
    String? mixMagnitudeRegressorVersion,
  }) {
    return AnalyticsEvent(
      aiPromptCycleFailedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'prompt_trace_id': promptTraceId,
        'error_code': errorCode,
        'tool_name': toolName,
        'model_name': modelName,
        'runtime_config_fingerprint': runtimeConfigFingerprint,
        'has_system_prompt_override': hasSystemPromptOverride,
        'project_stats_ms': projectStatsMs,
        'proxy_roundtrip_ms': proxyRoundtripMs,
        'response_parse_ms': responseParseMs,
        'mix_plan_ms': mixPlanMs,
        'mix_model_heuristic_ms': mixModelHeuristicMs,
        'mix_model_onnx_ms': mixModelOnnxMs,
        'apply_mix_ms': applyMixMs,
        'prompt_cycle_total_ms': promptCycleTotalMs,
        'openai_api_ms': openAiApiMs,
        'provider_roundtrip_ms': providerRoundtripMs,
        'response_normalize_ms': responseNormalizeMs,
        'proxy_handler_ms_total': proxyHandlerMsTotal,
        'tokens_prompt': tokensPrompt,
        'tokens_completion': tokensCompletion,
        'tokens_total': tokensTotal,
        'cached_prompt_tokens': cachedPromptTokens,
        'estimated_cost_usd': estimatedCostUsd,
        'mix_magnitude_model_source': mixMagnitudeModelSource,
        'mix_magnitude_model_bundle_version': mixMagnitudeModelBundleVersion,
        'mix_apply_model_version': mixApplyModelVersion,
        'mix_magnitude_regressor_version': mixMagnitudeRegressorVersion,
        'success': false,
      }),
    );
  }

  static AnalyticsEvent aiMagnitudeModelUpdate({
    required String status,
    String? mixMagnitudeModelSource,
    String? mixMagnitudeModelBundleVersion,
    String? mixApplyModelVersion,
    String? mixMagnitudeRegressorVersion,
    String? errorCode,
  }) {
    return AnalyticsEvent(
      aiMagnitudeModelUpdateName,
      properties: _compact(<String, Object?>{
        'status': status,
        'mix_magnitude_model_source': mixMagnitudeModelSource,
        'mix_magnitude_model_bundle_version': mixMagnitudeModelBundleVersion,
        'mix_apply_model_version': mixApplyModelVersion,
        'mix_magnitude_regressor_version': mixMagnitudeRegressorVersion,
        'error_code': errorCode,
      }),
    );
  }

  static AnalyticsEvent welcomeOnboardingShown({
    required String campaignVersion,
    required String mediaType,
    required String mediaVersion,
  }) {
    return AnalyticsEvent(
      welcomeOnboardingShownName,
      properties: _compact(<String, Object?>{
        'campaign_version': campaignVersion,
        'media_type': mediaType,
        'media_version': mediaVersion,
      }),
    );
  }

  static AnalyticsEvent welcomeOnboardingCompleted({
    required String campaignVersion,
    required String mediaType,
    required String mediaVersion,
    required String action,
  }) {
    return AnalyticsEvent(
      welcomeOnboardingCompletedName,
      properties: _compact(<String, Object?>{
        'campaign_version': campaignVersion,
        'media_type': mediaType,
        'media_version': mediaVersion,
        'action': action,
      }),
    );
  }

  static AnalyticsEvent remoteAnnouncementUpdate({
    required String status,
    String? announcementVersion,
    String? presentationMode,
    String? style,
    String? mediaType,
    String? mediaVersion,
    String? errorCode,
  }) {
    return AnalyticsEvent(
      remoteAnnouncementUpdateName,
      properties: _compact(<String, Object?>{
        'status': status,
        'announcement_version': announcementVersion,
        'presentation_mode': presentationMode,
        'style': style,
        'media_type': mediaType,
        'media_version': mediaVersion,
        'error_code': errorCode,
      }),
    );
  }

  static AnalyticsEvent remoteAnnouncementShown({
    required String announcementVersion,
    required String presentationMode,
    required String style,
    String? mediaType,
    String? mediaVersion,
  }) {
    return AnalyticsEvent(
      remoteAnnouncementShownName,
      properties: _compact(<String, Object?>{
        'announcement_version': announcementVersion,
        'presentation_mode': presentationMode,
        'style': style,
        'media_type': mediaType,
        'media_version': mediaVersion,
      }),
    );
  }

  static AnalyticsEvent remoteAnnouncementInteracted({
    required String announcementVersion,
    required String presentationMode,
    required String style,
    required String action,
    String? mediaType,
    String? mediaVersion,
    String? actionUrl,
    String? errorCode,
  }) {
    return AnalyticsEvent(
      remoteAnnouncementInteractedName,
      properties: _compact(<String, Object?>{
        'announcement_version': announcementVersion,
        'presentation_mode': presentationMode,
        'style': style,
        'action': action,
        'media_type': mediaType,
        'media_version': mediaVersion,
        'action_url': actionUrl,
        'error_code': errorCode,
      }),
    );
  }

  static AnalyticsEvent aiToolCalled({
    required String toolName,
    required String projectId,
    String? promptTraceId,
  }) {
    return AnalyticsEvent(
      aiToolCalledName,
      properties: _compact(<String, Object?>{
        'tool_name': toolName,
        'project_id': projectId,
        'prompt_trace_id': promptTraceId,
      }),
    );
  }

  static AnalyticsEvent aiUsageLimitHit({
    required String limitType,
  }) {
    return AnalyticsEvent(
      aiUsageLimitHitName,
      properties: _compact(<String, Object?>{
        'limit_type': limitType,
      }),
    );
  }

  static AnalyticsEvent subscriptionStarted({
    required String plan,
    String? price,
    String? billingCycle,
  }) {
    return AnalyticsEvent(
      subscriptionStartedName,
      properties: _compact(<String, Object?>{
        'plan': plan,
        'price': price,
        'billing_cycle': billingCycle,
      }),
    );
  }

  static AnalyticsEvent purchaseFailed({
    required String errorCode,
  }) {
    return AnalyticsEvent(
      purchaseFailedName,
      properties: _compact(<String, Object?>{
        'error_code': errorCode,
      }),
    );
  }

  static Map<String, Object?> _compact(Map<String, Object?> values) {
    return Map<String, Object?>.fromEntries(
      values.entries.where((entry) {
        final value = entry.value;
        if (value == null) return false;
        if (value is String) return value.trim().isNotEmpty;
        return true;
      }),
    );
  }
}
