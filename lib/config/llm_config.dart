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

  static bool get canUseDirectOpenAi =>
      hasOpenAiApiKey &&
      hasOpenAiModel &&
      (kDebugMode || allowDirectOpenAiInRelease);

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
