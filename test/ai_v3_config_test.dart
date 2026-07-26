import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/config/llm_config.dart';

void main() {
  test('V3 is disabled by default', () {
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
