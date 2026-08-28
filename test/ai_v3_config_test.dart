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
    expect(LlmConfig.aiV3PrimaryEnabled, expectedPrimary);
    expect(LlmConfig.aiV3ProxyPath, '/v1/llm/v3/responses');
    expect(LlmConfig.effectiveAiV3ProxyEnabled, expectedPrimary);
    expect(LlmConfig.effectiveAiV3Enabled, expectedPrimary);
    expect(LlmConfig.aiV3ResourceRefsEnabled, expectedResourceRefs);
    expect(LlmConfig.aiLiveEvaluationEnabled, isFalse);
  });
}
