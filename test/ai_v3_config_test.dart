import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/config/llm_config.dart';

void main() {
  test('build selects authenticated context-only V3 or the V1 kill switch', () {
    const expectedPrimary = bool.fromEnvironment(
      'AI_V3_PRIMARY_ENABLED',
      defaultValue: true,
    );
    const expectedResourceRefs = bool.fromEnvironment(
      'AI_V3_RESOURCE_REFS_ENABLED',
      defaultValue: true,
    );
    const expectedRequestTimeoutSeconds = int.fromEnvironment(
      'LLM_REQUEST_TIMEOUT_SECONDS',
      defaultValue: 25,
    );
    const expectedAiV3RequestTimeoutSeconds = int.fromEnvironment(
      'AI_V3_REQUEST_TIMEOUT_SECONDS',
      defaultValue: 35,
    );
    const expectedLongPathEnabled = bool.fromEnvironment(
      'AI_V3_LONG_PATH_ENABLED',
      defaultValue: false,
    );
    const expectedLongApiBaseUrl = String.fromEnvironment(
      'AI_V3_LONG_API_BASE_URL',
      defaultValue: '',
    );
    expect(LlmConfig.aiV3PrimaryEnabled, expectedPrimary);
    expect(LlmConfig.aiV3ProxyPath, '/v1/llm/v3/responses');
    expect(LlmConfig.effectiveAiV3ProxyEnabled, expectedPrimary);
    expect(LlmConfig.effectiveAiV3Enabled, expectedPrimary);
    expect(LlmConfig.aiV3ResourceRefsEnabled, expectedResourceRefs);
    expect(LlmConfig.aiLiveEvaluationEnabled, isFalse);
    expect(LlmConfig.requestTimeoutSeconds, expectedRequestTimeoutSeconds);
    expect(
      LlmConfig.aiV3RequestTimeoutSeconds,
      expectedAiV3RequestTimeoutSeconds,
    );
    expect(LlmConfig.aiV3LongPathEnabled, expectedLongPathEnabled);
    expect(LlmConfig.aiV3LongApiBaseUrl, expectedLongApiBaseUrl);

    final effectiveRoute = LlmConfig.effectiveAiV3RequestRoute;
    final expectedUseLongPath =
        LlmConfig.effectiveProxyApiBaseUrl.isNotEmpty &&
        expectedLongPathEnabled &&
        expectedLongApiBaseUrl.trim().isNotEmpty;
    expect(effectiveRoute.usesLongPath, expectedUseLongPath);
    expect(
      effectiveRoute.requestTimeoutSeconds,
      expectedUseLongPath ? 130 : expectedAiV3RequestTimeoutSeconds,
    );
    if (!expectedUseLongPath) {
      expect(
        effectiveRoute.proxyApiBaseUrl,
        LlmConfig.effectiveProxyApiBaseUrl,
      );
    }
  });

  test('V3 long route requires both its flag and URL', () {
    for (final input in <({bool enabled, String url})>[
      (enabled: false, url: ''),
      (enabled: true, url: ''),
      (enabled: true, url: '   '),
      (enabled: false, url: 'https://long.example/prod'),
    ]) {
      final route = LlmConfig.resolveAiV3RequestRoute(
        standardApiBaseUrl: 'https://standard.example/prod',
        standardTimeoutSeconds: 35,
        longPathEnabled: input.enabled,
        longApiBaseUrl: input.url,
      );
      expect(route.usesLongPath, isFalse, reason: '$input');
      expect(route.proxyApiBaseUrl, 'https://standard.example/prod');
      expect(route.requestTimeoutSeconds, 35);
    }
  });

  test('V3 long route is isolated and uses the 130-second client window', () {
    final route = LlmConfig.resolveAiV3RequestRoute(
      standardApiBaseUrl: 'https://standard.example/prod',
      standardTimeoutSeconds: 35,
      longPathEnabled: true,
      longApiBaseUrl: ' https://long.example/prod/ ',
    );

    expect(route.usesLongPath, isTrue);
    expect(route.proxyApiBaseUrl, 'https://long.example/prod/');
    expect(route.requestTimeoutSeconds, 130);
  });

  test('global proxy disablement cannot be bypassed by the V3 long route', () {
    final route = LlmConfig.resolveAiV3RequestRoute(
      standardApiBaseUrl: '',
      standardTimeoutSeconds: 35,
      longPathEnabled: true,
      longApiBaseUrl: 'https://long.example/prod',
    );

    expect(route.usesLongPath, isFalse);
    expect(route.proxyApiBaseUrl, isEmpty);
    expect(route.requestTimeoutSeconds, 35);
  });

  test('invalid long URLs fail closed to the unchanged standard route', () {
    for (final url in <String>[
      'long.example/prod',
      '/prod',
      'ftp://long.example/prod',
      'https:///prod',
      'https://user:secret@long.example/prod',
      'https://long.example/prod?route=long',
      'https://long.example/prod#long',
    ]) {
      final route = LlmConfig.resolveAiV3RequestRoute(
        standardApiBaseUrl: 'https://standard.example/prod',
        standardTimeoutSeconds: 35,
        longPathEnabled: true,
        longApiBaseUrl: url,
      );

      expect(route.usesLongPath, isFalse, reason: url);
      expect(route.proxyApiBaseUrl, 'https://standard.example/prod');
      expect(route.requestTimeoutSeconds, 35);
    }
  });

  test('long route must be distinct from the standard API', () {
    for (final url in <String>[
      'https://standard.example/prod',
      'https://STANDARD.example/prod/',
    ]) {
      final route = LlmConfig.resolveAiV3RequestRoute(
        standardApiBaseUrl: 'https://standard.example/prod/',
        standardTimeoutSeconds: 35,
        longPathEnabled: true,
        longApiBaseUrl: url,
      );

      expect(route.usesLongPath, isFalse, reason: url);
      expect(route.proxyApiBaseUrl, 'https://standard.example/prod/');
      expect(route.requestTimeoutSeconds, 35);
    }
  });

  test('HTTP long routes are limited to development loopback', () {
    for (final allowLoopback in [false, true]) {
      for (final entry in <({String url, bool loopback})>[
        (url: 'http://127.0.0.1:18766', loopback: true),
        (url: 'http://[::1]:18766', loopback: true),
        (url: 'http://localhost:18766', loopback: true),
        (url: 'http://long.example/prod', loopback: false),
        (url: 'http://192.168.1.2:18766', loopback: false),
        (url: 'http://localhost.example:18766', loopback: false),
        (url: 'http://127.0.0.1.example:18766', loopback: false),
        (url: 'http://0.0.0.0:18766', loopback: false),
      ]) {
        final route = LlmConfig.resolveAiV3RequestRoute(
          standardApiBaseUrl: 'https://standard.example/prod',
          standardTimeoutSeconds: 35,
          longPathEnabled: true,
          longApiBaseUrl: entry.url,
          allowInsecureLoopback: allowLoopback,
        );
        final expected = allowLoopback && entry.loopback;
        expect(
          route.usesLongPath,
          expected,
          reason: '${entry.url}, $allowLoopback',
        );
        expect(route.requestTimeoutSeconds, expected ? 130 : 35);
        expect(
          route.proxyApiBaseUrl,
          expected ? entry.url : 'https://standard.example/prod',
        );
      }
    }
  });

  test('long execute-api URL uses the configured stage normalization', () {
    final route = LlmConfig.resolveAiV3RequestRoute(
      standardApiBaseUrl: 'https://standard.example/prod',
      standardTimeoutSeconds: 35,
      longPathEnabled: true,
      longApiBaseUrl: 'https://abc123.execute-api.ap-northeast-2.amazonaws.com',
    );

    expect(
      route.proxyApiBaseUrl,
      'https://abc123.execute-api.ap-northeast-2.amazonaws.com/prod',
    );
    expect(route.requestTimeoutSeconds, 130);
  });
}
