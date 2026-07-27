import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/ai_model_cost.dart';

void main() {
  test('estimates GPT-5.6 Luna cache reads and writes separately', () {
    final estimate = estimateOpenAiModelCost(
      model: 'gpt-5.6-luna-2026-07-01',
      serviceTier: 'default',
      usage: const <String, dynamic>{
        'input_tokens': 10000,
        'input_tokens_details': <String, dynamic>{
          'cached_tokens': 2000,
          'cache_write_tokens': 3000,
        },
        'output_tokens': 1000,
      },
    );

    expect(estimate, isNotNull);
    expect(estimate?['uncached_input_tokens'], 5000);
    expect(estimate?['cached_input_tokens'], 2000);
    expect(estimate?['cache_write_input_tokens'], 3000);
    expect(estimate?['estimated_cost_usd'], closeTo(0.01495, 0.000000001));
  });

  test('estimates GPT-5.4 mini usage with cached input', () {
    final estimate = estimateOpenAiModelCost(
      model: 'gpt-5.4-mini',
      usage: const <String, dynamic>{
        'input_tokens': 10000,
        'input_tokens_details': <String, dynamic>{'cached_tokens': 2000},
        'output_tokens': 1000,
      },
    );

    expect(estimate, isNotNull);
    expect(estimate?['uncached_input_tokens'], 8000);
    expect(estimate?['cached_input_tokens'], 2000);
    expect(estimate?['cache_write_input_tokens'], 0);
    expect(estimate?['estimated_cost_usd'], closeTo(0.01065, 0.000000001));
  });
}
