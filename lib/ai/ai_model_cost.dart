class _AiTokenRates {
  const _AiTokenRates({
    required this.input,
    required this.cachedInput,
    required this.output,
    this.cacheWriteInput,
  });

  final double input;
  final double cachedInput;
  final double? cacheWriteInput;
  final double output;
}

const String _openAiPricingSource =
    'https://developers.openai.com/api/docs/pricing';
const String _pricingEffectiveDate = '2026-07-16';

const Map<String, Map<String, _AiTokenRates>> _ratesByTier =
    <String, Map<String, _AiTokenRates>>{
  'standard': <String, _AiTokenRates>{
    'gpt-5.4-mini': _AiTokenRates(
      input: 0.75,
      cachedInput: 0.075,
      output: 4.5,
    ),
    'gpt-5.6-luna': _AiTokenRates(
      input: 1,
      cachedInput: 0.1,
      cacheWriteInput: 1.25,
      output: 6,
    ),
  },
  'flex': <String, _AiTokenRates>{
    'gpt-5.4-mini': _AiTokenRates(
      input: 0.375,
      cachedInput: 0.0375,
      output: 2.25,
    ),
    'gpt-5.6-luna': _AiTokenRates(
      input: 0.5,
      cachedInput: 0.05,
      cacheWriteInput: 0.625,
      output: 3,
    ),
  },
  'priority': <String, _AiTokenRates>{
    'gpt-5.4-mini': _AiTokenRates(
      input: 1.5,
      cachedInput: 0.15,
      output: 9,
    ),
    'gpt-5.6-luna': _AiTokenRates(
      input: 2,
      cachedInput: 0.2,
      cacheWriteInput: 2.5,
      output: 12,
    ),
  },
};

/// Estimates standard OpenAI token charges from the usage object returned by
/// the API. The raw token counts and rates are retained so captures remain
/// auditable when pricing changes.
Map<String, dynamic>? estimateOpenAiModelCost({
  required String model,
  required Map<String, dynamic> usage,
  String serviceTier = '',
}) {
  final canonicalModel = _canonicalPricedModel(model);
  if (canonicalModel == null) return null;

  final pricingTier = _pricingTier(serviceTier);
  final rates = _ratesByTier[pricingTier]?[canonicalModel];
  if (rates == null) return null;

  final inputTokens = _tokenCount(
    usage,
    const <String>['input_tokens', 'prompt_tokens'],
  );
  final outputTokens = _tokenCount(
    usage,
    const <String>['output_tokens', 'completion_tokens'],
  );
  final details = _inputTokenDetails(usage);
  final reportedCachedTokens = _tokenCount(
    details,
    const <String>['cached_tokens'],
  );
  final reportedCacheWriteTokens = rates.cacheWriteInput == null
      ? 0
      : _tokenCount(
          details,
          const <String>['cache_write_tokens'],
        );

  final cacheWriteTokens =
      reportedCacheWriteTokens.clamp(0, inputTokens).toInt();
  final cachedTokens =
      reportedCachedTokens.clamp(0, inputTokens - cacheWriteTokens).toInt();
  final uncachedInputTokens = (inputTokens - cachedTokens - cacheWriteTokens)
      .clamp(0, inputTokens)
      .toInt();

  final longContext = canonicalModel == 'gpt-5.6-luna' && inputTokens > 272000;
  final inputMultiplier = longContext ? 2.0 : 1.0;
  final outputMultiplier = longContext ? 1.5 : 1.0;
  final cacheWriteRate = rates.cacheWriteInput ?? rates.input;
  final estimatedCost = ((uncachedInputTokens * rates.input * inputMultiplier) +
          (cachedTokens * rates.cachedInput * inputMultiplier) +
          (cacheWriteTokens * cacheWriteRate * inputMultiplier) +
          (outputTokens * rates.output * outputMultiplier)) /
      1000000.0;

  return <String, dynamic>{
    'currency': 'USD',
    'estimated_cost_usd': _roundUsd(estimatedCost),
    'model': canonicalModel,
    'service_tier_reported': serviceTier.trim(),
    'pricing_tier': pricingTier,
    'pricing_effective_date': _pricingEffectiveDate,
    'pricing_source': _openAiPricingSource,
    'input_tokens': inputTokens,
    'uncached_input_tokens': uncachedInputTokens,
    'cached_input_tokens': cachedTokens,
    'cache_write_input_tokens': cacheWriteTokens,
    'output_tokens': outputTokens,
    'rates_per_million_tokens': <String, dynamic>{
      'input': rates.input,
      'cached_input': rates.cachedInput,
      if (rates.cacheWriteInput != null)
        'cache_write_input': rates.cacheWriteInput,
      'output': rates.output,
    },
    if (longContext) ...<String, dynamic>{
      'long_context_pricing_applied': true,
      'input_rate_multiplier': inputMultiplier,
      'output_rate_multiplier': outputMultiplier,
    },
  };
}

String? _canonicalPricedModel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('gpt-5.6-luna')) return 'gpt-5.6-luna';
  if (normalized.startsWith('gpt-5.4-mini')) return 'gpt-5.4-mini';
  return null;
}

String _pricingTier(String value) {
  switch (value.trim().toLowerCase()) {
    case 'flex':
      return 'flex';
    case 'priority':
      return 'priority';
    case 'default':
    case 'standard':
    case 'auto':
    case '':
    default:
      return 'standard';
  }
}

Map<String, dynamic> _inputTokenDetails(Map<String, dynamic> usage) {
  for (final key in const <String>[
    'input_tokens_details',
    'prompt_tokens_details'
  ]) {
    final value = usage[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

int _tokenCount(Map<String, dynamic> value, List<String> keys) {
  for (final key in keys) {
    final raw = value[key];
    if (raw is num) return raw.toInt().clamp(0, 1 << 62).toInt();
  }
  return 0;
}

double _roundUsd(double value) =>
    (value * 1000000000000).roundToDouble() / 1000000000000;
