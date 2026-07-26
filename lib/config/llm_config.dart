import 'package:flutter/foundation.dart';

class LlmConfig {
  const LlmConfig._();

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

  static const bool allowDirectOpenAiInRelease = bool.fromEnvironment(
    'LLM_ALLOW_DIRECT_OPENAI_IN_RELEASE',
    defaultValue: false,
  );

  static const bool disableProxyInDebug = bool.fromEnvironment(
    'LLM_DISABLE_PROXY_IN_DEBUG',
    defaultValue: false,
  );

  /// Local debug-only one-shot V3 prototype. Release builds intentionally
  /// ignore this switch so V3 cannot bypass the authenticated proxy.
  static const bool aiV3PrototypeEnabled = bool.fromEnvironment(
    'AI_V3_PROTOTYPE_ENABLED',
    defaultValue: false,
  );

  static const String aiV3Model = String.fromEnvironment(
    'AI_V3_MODEL',
    defaultValue: 'gpt-5.6-luna',
  );

  static const String aiV3ReasoningEffort = String.fromEnvironment(
    'AI_V3_REASONING_EFFORT',
    defaultValue: 'low',
  );

  static const String aiV3ContextProfile = String.fromEnvironment(
    'AI_V3_CONTEXT_PROFILE',
    defaultValue: 'essential',
  );

  static const bool aiV3CaptureEnabled = bool.fromEnvironment(
    'AI_V3_CAPTURE_ENABLED',
    defaultValue: false,
  );

  static const bool aiV3DetachedComparisonsEnabled = bool.fromEnvironment(
    'AI_V3_DETACHED_COMPARISONS_ENABLED',
    defaultValue: true,
  );

  static const bool aiV3CompactShadowEvaluationEnabled = bool.fromEnvironment(
    'AI_V3_COMPACT_SHADOW_EVAL_ENABLED',
    defaultValue: false,
  );

  /// Detached adaptive evaluation only. It never supplies the visible plan.
  static const bool aiV3AdaptiveShadowEnabled = bool.fromEnvironment(
    'AI_V3_ADAPTIVE_SHADOW_ENABLED',
    defaultValue: false,
  );

  static const String aiV3AdaptiveComparisonModel = String.fromEnvironment(
    'AI_V3_ADAPTIVE_COMPARISON_MODEL',
    defaultValue: '',
  );

  static const String aiV3CaptureDirectory = String.fromEnvironment(
    'AI_V3_CAPTURE_DIR',
    defaultValue: 'tool/ai_v3_captures.local',
  );

  static const bool aiLiveEvaluationEnabled = bool.fromEnvironment(
    'AI_LIVE_EVAL',
    defaultValue: false,
  );

  static bool get effectiveAiV3PrototypeEnabled =>
      kDebugMode && aiV3PrototypeEnabled && canUseDirectOpenAi;

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
      hasOpenAiApiKey &&
      hasOpenAiModel &&
      (kDebugMode || allowDirectOpenAiInRelease);

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
}
