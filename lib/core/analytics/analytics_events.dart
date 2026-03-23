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
  }) {
    return AnalyticsEvent(
      aiPromptSubmittedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'model_name': modelName,
      }),
    );
  }

  static AnalyticsEvent aiResponseCompleted({
    required String projectId,
    required String aiFeature,
    String? modelName,
    int? latencyMs,
    int? tokensPrompt,
    int? tokensCompletion,
    int? tokensTotal,
  }) {
    return AnalyticsEvent(
      aiResponseCompletedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'model_name': modelName,
        'latency_ms': latencyMs,
        'tokens_prompt': tokensPrompt,
        'tokens_completion': tokensCompletion,
        'tokens_total': tokensTotal,
        'success': true,
      }),
    );
  }

  static AnalyticsEvent aiResponseFailed({
    required String projectId,
    required String aiFeature,
    required String errorCode,
  }) {
    return AnalyticsEvent(
      aiResponseFailedName,
      properties: _compact(<String, Object?>{
        'project_id': projectId,
        'ai_feature': aiFeature,
        'error_code': errorCode,
        'success': false,
      }),
    );
  }

  static AnalyticsEvent aiToolCalled({
    required String toolName,
    required String projectId,
  }) {
    return AnalyticsEvent(
      aiToolCalledName,
      properties: _compact(<String, Object?>{
        'tool_name': toolName,
        'project_id': projectId,
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
