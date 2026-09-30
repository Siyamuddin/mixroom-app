import 'package:flutter/foundation.dart';

class AiV3RequestRoute {
  const AiV3RequestRoute({
    required this.proxyApiBaseUrl,
    required this.requestTimeoutSeconds,
    required this.usesLongPath,
  });

  final String proxyApiBaseUrl;
  final int requestTimeoutSeconds;
  final bool usesLongPath;
}

class LlmConfig {
  const LlmConfig._();

  /// Keep local refinement testing independent of the hosted chat planner.
  static String get effectiveMixResolveBaseUrl {
    const local = String.fromEnvironment('MIXROOM_LOCAL_REFINE_URL');
    return kDebugMode && local.trim().isNotEmpty
        ? local.trim().replaceFirst(RegExp(r'/+$'), '')
        : effectiveProxyApiBaseUrl;
  }

  static const String _defaultProxyApiBaseUrl =
      'https://3mbfa2dx50.execute-api.ap-northeast-2.amazonaws.com/prod';

  static const String proxyApiBaseUrl = String.fromEnvironment(
    'LLM_PROXY_API_BASE_URL',
    defaultValue: '',
  );

  static const String proxyPath = String.fromEnvironment(
    'LLM_PROXY_PATH',
    defaultValue: '/v1/llm/responses',
  );

  static const String aiV3ProxyPath = String.fromEnvironment(
    'AI_V3_PROXY_PATH',
    defaultValue: '/v1/llm/v3/responses',
  );

  static const String _legacyMixResolvePath = String.fromEnvironment(
    'LLM_MIX_RESOLVE_PATH',
    defaultValue: '',
  );

  static const String _proxyMixResolvePath = String.fromEnvironment(
    'LLM_PROXY_MIX_RESOLVE_PATH',
    defaultValue: '',
  );

  static const String proxyStage = String.fromEnvironment(
    'LLM_PROXY_STAGE',
    defaultValue: 'prod',
  );

  static const String openAiApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static const String openAiModel = String.fromEnvironment(
    'OPENAI_MODEL',
    defaultValue: '',
  );

  static const String conversationStateMode = String.fromEnvironment(
    'LLM_CONVERSATION_STATE_MODE',
    defaultValue: 'openai_conversation_seeded',
  );

  static const String contextPackingMode = String.fromEnvironment(
    'LLM_CONTEXT_PACKING_MODE',
    defaultValue: 'compact',
  );

  static const String toolRoutingMode = String.fromEnvironment(
    'LLM_TOOL_ROUTING_MODE',
    defaultValue: 'intent_scoped',
  );

  static const int requestTimeoutSeconds = int.fromEnvironment(
    'LLM_REQUEST_TIMEOUT_SECONDS',
    defaultValue: 25,
  );

  // Outlast the 30-second HTTP API window so V3 can receive the backend's
  // controlled timeout response instead of abandoning the request first.
  static const int aiV3RequestTimeoutSeconds = int.fromEnvironment(
    'AI_V3_REQUEST_TIMEOUT_SECONDS',
    defaultValue: 35,
  );

  /// Enabled for updated clients after the long route passed its backend and
  /// compatibility rollout gates. Builds can set this to false as a kill
  /// switch; a valid, distinct URL is still required before V3 changes route.
  static const bool aiV3LongPathEnabled = bool.fromEnvironment(
    'AI_V3_LONG_PATH_ENABLED',
    defaultValue: true,
  );

  /// Public endpoint only; provider credentials, prompts, schemas, model
  /// settings, and repair logic remain in the backend.
  static const String aiV3LongApiBaseUrl = String.fromEnvironment(
    'AI_V3_LONG_API_BASE_URL',
    defaultValue:
        'https://5px4k98xz2.execute-api.ap-northeast-2.amazonaws.com/prod',
  );

  static const int _aiV3LongRequestTimeoutSeconds = 130;

  static const bool disableProxyInDebug = bool.fromEnvironment(
    'LLM_DISABLE_PROXY_IN_DEBUG',
    defaultValue: false,
  );

  static const String n8nSecretHeaderName = String.fromEnvironment(
    'MIXROOM_N8N_SECRET_HEADER',
    defaultValue: '',
  );

  static const String n8nSecretHeaderValue = String.fromEnvironment(
    'MIXROOM_N8N_SECRET',
    defaultValue: '',
  );

  /// Debug-only extra proxy headers, for example an n8n webhook secret.
  static Map<String, String> get debugProxyExtraHeaders {
    if (!kDebugMode) return const <String, String>{};
    final name = n8nSecretHeaderName.trim();
    final value = n8nSecretHeaderValue.trim();
    if (name.isEmpty || value.isEmpty) return const <String, String>{};
    return <String, String>{name: value};
  }

  /// Primary route for updated clients. Set false at build time to retain V1
  /// as the visible planner without removing either implementation.
  static const bool aiV3PrimaryEnabled = bool.fromEnvironment(
    'AI_V3_PRIMARY_ENABLED',
    defaultValue: true,
  );

  static const String aiV3ContextProfile = String.fromEnvironment(
    'AI_V3_CONTEXT_PROFILE',
    defaultValue: 'essential',
  );

  static const bool aiV3ResourceRefsEnabled = bool.fromEnvironment(
    'AI_V3_RESOURCE_REFS_ENABLED',
    defaultValue: true,
  );

  static const bool aiLiveEvaluationEnabled = bool.fromEnvironment(
    'AI_LIVE_EVAL',
    defaultValue: false,
  );

  static bool get effectiveAiV3ProxyEnabled =>
      aiV3PrimaryEnabled && hasProxyApiBaseUrl;

  static bool get effectiveAiV3Enabled => effectiveAiV3ProxyEnabled;

  static AiV3RequestRoute get effectiveAiV3RequestRoute =>
      resolveAiV3RequestRoute(
        standardApiBaseUrl: effectiveProxyApiBaseUrl,
        standardTimeoutSeconds: aiV3RequestTimeoutSeconds,
        longPathEnabled: aiV3LongPathEnabled,
        longApiBaseUrl: aiV3LongApiBaseUrl,
      );

  static AiV3RequestRoute resolveAiV3RequestRoute({
    required String standardApiBaseUrl,
    required int standardTimeoutSeconds,
    required bool longPathEnabled,
    required String longApiBaseUrl,
    bool allowInsecureLoopback = kDebugMode,
  }) {
    final normalizedStandardUrl = standardApiBaseUrl.trim();
    final rawLongUrl = longApiBaseUrl.trim();
    final normalizedLongUrl = _isValidLongApiBaseUrl(
      rawLongUrl,
      allowInsecureLoopback: allowInsecureLoopback,
    )
        ? _normalizeProxyApiBaseUrl(rawLongUrl)
        : '';
    final useLongPath =
        normalizedStandardUrl.isNotEmpty &&
        longPathEnabled &&
        normalizedLongUrl.isNotEmpty &&
        !_sameProxyApiBaseUrl(normalizedStandardUrl, normalizedLongUrl);
    return AiV3RequestRoute(
      proxyApiBaseUrl: useLongPath ? normalizedLongUrl : normalizedStandardUrl,
      requestTimeoutSeconds: useLongPath
          ? _aiV3LongRequestTimeoutSeconds
          : standardTimeoutSeconds,
      usesLongPath: useLongPath,
    );
  }

  static String get effectiveProxyApiBaseUrl {
    if (kDebugMode && disableProxyInDebug) {
      return '';
    }
    final configured = proxyApiBaseUrl.trim();
    if (configured.isNotEmpty) {
      return _normalizeProxyApiBaseUrl(configured);
    }
    return _normalizeProxyApiBaseUrl(_defaultProxyApiBaseUrl);
  }

  static bool get hasProxyApiBaseUrl => effectiveProxyApiBaseUrl.isNotEmpty;

  static bool get hasOpenAiApiKey => openAiApiKey.trim().isNotEmpty;

  static bool get hasOpenAiModel => openAiModel.trim().isNotEmpty;

  static String get mixResolvePath {
    final configured = _proxyMixResolvePath.trim().isNotEmpty
        ? _proxyMixResolvePath
        : _legacyMixResolvePath;
    final trimmed = configured.trim();
    return trimmed.isEmpty ? '/v1/mix/resolve' : trimmed;
  }

  static bool get canUseDirectOpenAi =>
      kDebugMode && hasOpenAiApiKey && hasOpenAiModel;

  static String get normalizedConversationStateMode {
    final normalized = conversationStateMode.trim().toLowerCase();
    switch (normalized) {
      case 'openai_conversation_seeded':
        return 'openai_conversation_seeded';
      case 'openai_conversation':
        return 'openai_conversation';
      case 'manual_history':
      default:
        return 'manual_history';
    }
  }

  static String get normalizedContextPackingMode {
    final normalized = contextPackingMode.trim().toLowerCase();
    switch (normalized) {
      case 'compact':
        return 'compact';
      case 'full':
      default:
        return 'full';
    }
  }

  static String get normalizedToolRoutingMode {
    final normalized = toolRoutingMode.trim().toLowerCase();
    return normalized == 'intent_scoped' ? 'intent_scoped' : 'full';
  }

  static String _normalizeProxyApiBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    final stage = proxyStage.trim();
    final hasExecuteApiHost = uri.host.contains('.execute-api.');
    final path = uri.path.trim();
    final hasStagePath = path.isNotEmpty && path != '/';

    if (!hasExecuteApiHost || hasStagePath || stage.isEmpty) {
      return trimmed;
    }

    final normalizedBase = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return '$normalizedBase/$stage';
  }

  static bool _isValidLongApiBaseUrl(
    String raw, {
    required bool allowInsecureLoopback,
  }) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    // Never send bearer credentials over remote HTTP. The exception is only
    // for opt-in debug bridges, not release/profile builds or LAN endpoints.
    return allowInsecureLoopback &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  }

  static bool _sameProxyApiBaseUrl(String left, String right) {
    String identity(String raw) {
      final normalized = _normalizeProxyApiBaseUrl(raw.trim());
      final withoutTrailingSlash = normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
      final uri = Uri.tryParse(withoutTrailingSlash);
      if (uri == null || !uri.hasAuthority) return withoutTrailingSlash;
      return uri
          .replace(
            scheme: uri.scheme.toLowerCase(),
            host: uri.host.toLowerCase(),
          )
          .toString();
    }

    return identity(left) == identity(right);
  }
}
