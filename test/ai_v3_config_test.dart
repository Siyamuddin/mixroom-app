import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/config/llm_config.dart';

void main() {
  test('build selects authenticated one-shot V3 or the V1 kill switch', () {
    const expectedPrimary = bool.fromEnvironment(
      'AI_V3_PRIMARY_ENABLED',
      defaultValue: true,
    );
    expect(LlmConfig.aiV3PrimaryEnabled, expectedPrimary);
    expect(LlmConfig.aiV3ProxyPath, '/v1/llm/v3/responses');
    expect(LlmConfig.effectiveAiV3ProxyEnabled, expectedPrimary);
    expect(LlmConfig.effectiveAiV3Enabled, expectedPrimary);
    expect(LlmConfig.aiV3PrototypeEnabled, isFalse);
    expect(LlmConfig.effectiveAiV3PrototypeEnabled, isFalse);
    expect(LlmConfig.aiV3Model, 'gpt-5.6-luna');
    expect(LlmConfig.aiV3ReasoningEffort, 'low');
    expect(LlmConfig.aiV3CaptureEnabled, isFalse);
    expect(LlmConfig.aiV3DetachedComparisonsEnabled, isTrue);
    expect(LlmConfig.aiV3CompactShadowEvaluationEnabled, isFalse);
    expect(LlmConfig.aiV3AdaptiveShadowEnabled, isFalse);
    expect(LlmConfig.aiV3AdaptiveComparisonModel, isEmpty);
    expect(LlmConfig.aiLiveEvaluationEnabled, isFalse);
  });
}
