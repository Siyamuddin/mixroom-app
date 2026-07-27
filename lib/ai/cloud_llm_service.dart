import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/models/mixing_result.dart';

import 'package:mixroom/ai/ai_debug.dart';
import 'package:mixroom/ai/assistant_action_utils.dart';
import 'package:mixroom/ai/debug_system_prompt.dart';
import 'package:mixroom/ai/ai_execution_guidance.dart';

class AiPromptRateLimitWindow {
  final int used;
  final int limit;
  final int remaining;
  final DateTime? resetsAt;

  const AiPromptRateLimitWindow({
    required this.used,
    required this.limit,
    required this.remaining,
    required this.resetsAt,
  });

  double get remainingFraction {
    if (limit <= 0) return remaining > 0 ? 1.0 : 0.0;
    return (remaining / limit).clamp(0.0, 1.0).toDouble();
  }

  int get remainingPercent => (remainingFraction * 100).round();

  factory AiPromptRateLimitWindow.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    final resetsAtRaw = data['resets_at']?.toString().trim() ?? '';
    return AiPromptRateLimitWindow(
      used: (data['used'] as num?)?.toInt() ?? 0,
      limit: (data['limit'] as num?)?.toInt() ?? 0,
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      resetsAt: resetsAtRaw.isEmpty ? null : DateTime.tryParse(resetsAtRaw),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'used': used,
      'limit': limit,
      'remaining': remaining,
      if (resetsAt != null) 'resets_at': resetsAt!.toIso8601String(),
    };
  }
}

class AiPromptBankStatus {
  final int remaining;
  final bool consumedFirst;

  const AiPromptBankStatus({
    required this.remaining,
    required this.consumedFirst,
  });

  bool get available => remaining > 0;

  factory AiPromptBankStatus.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return AiPromptBankStatus(
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      consumedFirst: data['consumed_first'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'remaining': remaining, 'consumed_first': consumedFirst};
  }
}

class AiPromptRateLimitStatus {
  final AiPromptRateLimitWindow daily;
  final AiPromptRateLimitWindow weekly;
  final AiPromptBankStatus extraPromptBank;
  final bool canSubmit;
  final String blockedBy;

  const AiPromptRateLimitStatus({
    required this.daily,
    required this.weekly,
    required this.extraPromptBank,
    required this.canSubmit,
    required this.blockedBy,
  });

  bool get isBlocked => !canSubmit;

  DateTime? get blockedResetAt {
    switch (blockedBy) {
      case 'weekly_prompts':
        return weekly.resetsAt;
      case 'daily_prompts':
        return daily.resetsAt;
      default:
        return null;
    }
  }

  factory AiPromptRateLimitStatus.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return AiPromptRateLimitStatus(
      daily: AiPromptRateLimitWindow.fromJson(
        (data['daily'] as Map?)?.cast<String, dynamic>(),
      ),
      weekly: AiPromptRateLimitWindow.fromJson(
        (data['weekly'] as Map?)?.cast<String, dynamic>(),
      ),
      extraPromptBank: AiPromptBankStatus.fromJson(
        (data['extra_prompt_bank'] as Map?)?.cast<String, dynamic>(),
      ),
      canSubmit: data['can_submit'] != false,
      blockedBy: data['blocked_by']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'daily': daily.toJson(),
      'weekly': weekly.toJson(),
      'extra_prompt_bank': extraPromptBank.toJson(),
      'can_submit': canSubmit,
      'blocked_by': blockedBy,
    };
  }
}

class _PackedContextSnapshots {
  final String projectSnapshot;
  final String selectionSnapshot;
  final String librarySnapshot;

  const _PackedContextSnapshots({
    required this.projectSnapshot,
    required this.selectionSnapshot,
    required this.librarySnapshot,
  });
}

class LlmResult {
  final String? text; // assistant text (optional)
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final Map<String, dynamic>? meta;

  bool get hasToolCall => toolName != null && toolArgs != null;

  const LlmResult({this.text, this.toolName, this.toolArgs, this.meta});

  factory LlmResult.text(
    String text,
    Map<String, dynamic>? toolArgs, {
    Map<String, dynamic>? meta,
  }) => LlmResult(
    text: text,
    toolName: 'informational_response',
    toolArgs: toolArgs,
    meta: meta,
  );

  factory LlmResult.tool(
    String toolName,
    Map<String, dynamic> toolArgs, {
    String? text,
    Map<String, dynamic>? meta,
  }) =>
      LlmResult(text: text, toolName: toolName, toolArgs: toolArgs, meta: meta);
}

class CloudLlmService {
  static const _apiUrl = 'https://api.openai.com/v1/responses';
  static const _conversationsApiUrl = 'https://api.openai.com/v1/conversations';
  static const _promptCacheVersion = 'mixroom-daw-v20260701a';
  static const _directOpenAiMaxOutputTokens = 8192;
  static const _defaultPromptCacheRetention = 'in_memory';
  static const _recoverableAuthMessage =
      "I couldn't reach the AI service just now. Please try again in a moment.";
  static const _temporaryFailureMessage =
      "I couldn't complete that request just now. Please try again in a moment.";
  static const Set<String> _extendedPromptCacheRetentionModels = {
    'gpt-4.1',
    'gpt-5',
    'gpt-5-codex',
    'gpt-5.1',
    'gpt-5.1-codex',
    'gpt-5.1-codex-mini',
    'gpt-5.1-chat-latest',
    'gpt-5.2',
    'gpt-5.4-mini',
  };

  final String apiKey;
  final String model;
  final String proxyApiBaseUrl;
  final String proxyPath;
  final Future<String?> Function()? authTokenProvider;
  final Future<String?> Function()? refreshAuthTokenProvider;
  final Duration requestTimeout;
  final String conversationStateMode;
  final http.Client _httpClient;
  final Map<String, String> _directConversationIds = <String, String>{};
  final Map<String, int> _conversationTurnCounts = <String, int>{};

  CloudLlmService({
    this.apiKey = '',
    this.model = '',
    this.proxyApiBaseUrl = '',
    this.proxyPath = '/v1/llm/responses',
    this.authTokenProvider,
    this.refreshAuthTokenProvider,
    this.requestTimeout = const Duration(seconds: 25),
    this.conversationStateMode = 'manual_history',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  bool get _supportsTemperature => !model.toLowerCase().startsWith('gpt-5');
  Map<String, dynamic>? get _defaultReasoning {
    final effort = _defaultReasoningEffort(model);
    return effort.isEmpty ? null : <String, dynamic>{'effort': effort};
  }

  String _promptCacheKeyForFeature(
    String aiFeature, {
    String? capabilitySignature,
  }) {
    final normalizedFeature = aiFeature.trim().isEmpty
        ? 'ai_chat'
        : aiFeature.trim();
    final normalizedCapabilities = (capabilitySignature ?? '').trim().isEmpty
        ? 'legacy'
        : capabilitySignature!.trim();
    final capabilityHash = crypto.sha256
        .convert(utf8.encode(normalizedCapabilities))
        .toString()
        .substring(0, 12);
    return '$_promptCacheVersion:$normalizedFeature:$capabilityHash';
  }

  String get _promptCacheRetention =>
      _extendedPromptCacheRetentionModels.contains(model.trim().toLowerCase())
      ? '24h'
      : _defaultPromptCacheRetention;
  bool get _canUseDirectOpenAi =>
      apiKey.trim().isNotEmpty && model.trim().isNotEmpty;
  bool get _isProxyEnabled => proxyApiBaseUrl.trim().isNotEmpty;
  bool get _isUsingDebugSystemPrompt =>
      kDebugMode && kDebugSystemPrompt.trim().isNotEmpty;
  String get _llmRouteLabel => _isProxyEnabled
      ? 'llm_proxy'
      : (_canUseDirectOpenAi ? 'direct_openai' : 'unconfigured');
  String get _promptSourceLabel {
    if (_isProxyEnabled) {
      return 'llm_proxy_system_prompt';
    }
    if (_isUsingDebugSystemPrompt) {
      return 'kDebugSystemPrompt_plus_client_overrides';
    }
    return 'missing_direct_openai_prompt';
  }

  String get _normalizedConversationStateMode =>
      _normalizeConversationStateMode(conversationStateMode);

  String _normalizeConversationStateMode(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'openai_conversation_seeded':
        return 'openai_conversation_seeded';
      case 'openai_conversation':
        return 'openai_conversation';
      case 'manual_history':
      default:
        return 'manual_history';
    }
  }

  bool get _usesOpenAiConversationState =>
      _normalizedConversationStateMode == 'openai_conversation' ||
      _normalizedConversationStateMode == 'openai_conversation_seeded';
  bool get _usesSeededOpenAiConversationState =>
      _normalizedConversationStateMode == 'openai_conversation_seeded';

  String get _effectiveSystemPrompt {
    final debugPrompt = kDebugMode ? kDebugSystemPrompt.trim() : '';
    return debugPrompt;
  }

  static const Set<String> _knownClientCapabilities = <String>{
    'daw.project_edit.set_tempo',
    'daw.sample_insert.library',
    'daw.midi_compose.instrument_insert',
    'daw.midi_compose.transpose_notes',
    'daw.midi_compose.audio_to_midi',
    'daw.transport_control',
    'daw.row_mute',
    'daw.row_solo',
    'daw.row_rename',
    'daw.row_select',
    'daw.row_delete',
    'daw.row_create',
    'daw.row_mix',
    'daw.automation_edit',
    'daw.clip_edit.pitch_shift',
    'daw.clean_content_rows',
  };

  Map<String, dynamic> _mergedAnalyticsClientContext(
    Map<String, dynamic> clientContext,
  ) {
    final requestContext = AnalyticsService.instance.buildRequestContext();
    final analyticsClientContext =
        (requestContext['client_context'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return <String, dynamic>{...analyticsClientContext, ...clientContext};
  }

  Set<String> _readClientCapabilities(Map<String, dynamic> clientContext) {
    final rawCapabilities = clientContext['ai_capabilities'];
    if (rawCapabilities is! List) return <String>{};
    return rawCapabilities
        .whereType<String>()
        .map((value) => value.trim())
        .where(
          (value) =>
              value.isNotEmpty && _knownClientCapabilities.contains(value),
        )
        .toSet();
  }

  String _readContextPackingMode(Map<String, dynamic> clientContext) {
    final normalized =
        clientContext['ai_context_packing_mode']
            ?.toString()
            .trim()
            .toLowerCase() ??
        'full';
    switch (normalized) {
      case 'compact':
        return 'compact';
      case 'full':
      default:
        return 'full';
    }
  }

  String _readToolRoutingMode(Map<String, dynamic> clientContext) {
    final normalized =
        clientContext['ai_tool_routing_mode']
            ?.toString()
            .trim()
            .toLowerCase() ??
        'full';
    return normalized == 'intent_scoped' ? 'intent_scoped' : 'full';
  }

  String _effectiveToolRoutingMode(Map<String, dynamic> clientContext) {
    return _readToolRoutingMode(clientContext);
  }

  String _contextRouteSignature(Map<String, dynamic> clientContext) {
    final contextPackingMode = _readContextPackingMode(clientContext);
    final toolRoutingMode = _readToolRoutingMode(clientContext);
    if (contextPackingMode == 'full' && toolRoutingMode == 'full') {
      return '';
    }
    return 'context:$contextPackingMode|tool_routing:$toolRoutingMode';
  }

  List<String> _readStringList(dynamic value, {int maxItems = 80}) {
    if (value is! List) return const <String>[];
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in value) {
      if (raw is! String) continue;
      final item = raw.trim();
      if (item.isEmpty || !seen.add(item)) continue;
      normalized.add(item);
      if (normalized.length >= maxItems) break;
    }
    return normalized;
  }

  int? _readNonNegativeInt(dynamic value) {
    if (value is bool) return null;
    if (value is int) return value >= 0 ? value : null;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed != null && parsed >= 0 ? parsed : null;
    }
    return null;
  }

  static final RegExp _trackLineRe = RegExp(r'^Track\s+(\d+):\s*(.*)$');
  static final RegExp _mixIntentRe = RegExp(
    r'\b(mix|master|eq|compress|compression|reverb|delay|space|spacious|depth|width|wide|wider|widen|narrow|stereo|spread|warm|warmer|warmth|body|fuller|thin|tone|bright|brighter|brighten|brightness|clear|clearer|clarity|dark|darker|dull|punch|presence|air|wet|wetter|dry|balance|loud|quiet|volume|bass|treble|vocal|instrumental|reference|remix|lofi|lo-fi|vibe)\b',
    caseSensitive: false,
  );
  static final RegExp _dawIntentRe = RegExp(
    r'\b(mute|unmute|solo|unsolo|split|stem|stems|separate|rename|select|delete|remove|add|insert|put|place|create|make|write|compose|generate|drum|kick|snare|hat|sample|loop|midi|instrument|pitch|transpose|tempo|bpm|play|pause|stop|restart|move|copy|duplicate|trim|cut|fade|automation|effect|plugin|row|track|clip|record|undo|redo|metronome|click|vinyl|noise|texture|riser|whoosh|fx|808|drop|duck|sidechain|pump|pan|left|right|center|adlib|hook|cleanup|clean)\b',
    caseSensitive: false,
  );
  static final RegExp _questionIntentRe = RegExp(
    r'\b(what|where|why|how|which|help|explain|tell me|show me)\b',
    caseSensitive: false,
  );

  String _extractInlineField(String text, String key) {
    final pattern = RegExp(
      '${RegExp.escape(key)}=("[^"]*"|\\[[^\\]]*\\]|\\{[^}]*\\}|[^\\s,}]+)',
    );
    return pattern.firstMatch(text)?.group(1)?.trim() ?? '';
  }

  String _extractInlineBlock(String text, String key) {
    final pattern = RegExp('${RegExp.escape(key)}\\{([^}]*)\\}');
    final match = pattern.firstMatch(text);
    final value = match?.group(1)?.trim() ?? '';
    return value.isEmpty ? '' : '{$value}';
  }

  String _compactTrackLine(String line) {
    final match = _trackLineRe.firstMatch(line.trim());
    if (match == null) return line.trim();

    final trackNumber = int.tryParse(match.group(1) ?? '') ?? 1;
    final rowIndex = math.max(0, trackNumber - 1);
    final rest = match.group(2) ?? '';
    final fields = <String>['row_index=$rowIndex', 'track_number=$trackNumber'];
    for (final key in const <String>[
      'row_name',
      'lane_kind',
      'clip_count',
      'clip_kinds',
      'labels',
      'files',
      'instruments',
      'sample_hints',
      'gain',
      'pan',
      'roles',
      'role_consistency',
      'reference_hints',
      'fx_count',
      'active_fx_count',
      'fx_chain',
      'automation_targets',
    ]) {
      final value = _extractInlineField(rest, key);
      if (value.isNotEmpty) fields.add('$key=$value');
    }
    for (final key in const <String>[
      'arrangement',
      'midi_state',
      'coverage',
      'interpretation',
    ]) {
      final value = _extractInlineBlock(rest, key);
      if (value.isNotEmpty) fields.add('$key=$value');
    }
    final notes = _extractInlineField(rest, 'notes');
    if (notes.isNotEmpty) fields.add('notes=$notes');
    return 'ROW ${fields.join(' ')}';
  }

  String _compactMasterLine(String line) {
    final rest = line.contains(':') ? line.split(':').skip(1).join(':') : line;
    final fields = <String>['MASTER'];
    for (final key in const <String>[
      'gain',
      'pan',
      'fx_count',
      'active_fx_count',
      'fx_chain',
      'automation_targets',
    ]) {
      final value = _extractInlineField(rest, key);
      if (value.isNotEmpty) fields.add('$key=$value');
    }
    return fields.join(' ');
  }

  String _compactProjectSnapshot(String snapshot) {
    final lines = <String>['COMPACT_PROJECT_SNAPSHOT_V1'];
    for (final raw in snapshot.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_trackLineRe.hasMatch(line)) {
        lines.add(_compactTrackLine(line));
        continue;
      }
      if (line.startsWith('Master:')) {
        lines.add(_compactMasterLine(line));
        continue;
      }
      if (const <String>[
        'bpm=',
        'project_key=',
        'occupied_tracks=',
        'top_occupied_track=',
        'empty_rows=',
        'row_count=',
      ].any((prefix) => line.startsWith(prefix))) {
        lines.add(line);
      }
    }
    return lines.join('\n').trim();
  }

  String _compactSelectedRowContext(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    final fields = <String>[];
    for (final key in const <String>[
      'row_index',
      'track_number',
      'row_name',
      'lane_kind',
      'clip_count',
      'clip_kinds',
      'labels',
      'files',
      'instruments',
      'sample_hints',
      'top_role',
      'source_type',
      'flags',
      'reference_hints',
      'fx_count',
      'active_fx_count',
      'fx_chain',
    ]) {
      final fieldValue = _extractInlineField(text, key);
      if (fieldValue.isNotEmpty) fields.add('$key=$fieldValue');
    }
    for (final key in const <String>['arrangement', 'midi_state', 'coverage']) {
      final blockValue = _extractInlineBlock(text, key);
      if (blockValue.isNotEmpty) fields.add('$key=$blockValue');
    }
    return fields.isEmpty ? text : 'selected_row_context{${fields.join(',')}}';
  }

  String _compactSelectionSnapshot(String snapshot) {
    final lines = <String>['COMPACT_SELECTION_SNAPSHOT_V1'];
    for (final raw in snapshot.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('selected_row_context{') && line.endsWith('}')) {
        final inner = line.substring(
          'selected_row_context{'.length,
          line.length - 1,
        );
        final compact = _compactSelectedRowContext(inner);
        if (compact.isNotEmpty) lines.add(compact);
        continue;
      }
      if (const <String>[
        'selected_row_index=',
        'selected_clip_indices=',
        'primary_selected_clip_index=',
        'selected_clip[',
        'occupied_tracks=',
        'top_occupied_track=',
        'master_automation_targets=',
        'selected_row_automation_targets=',
        'master_context',
      ].any((prefix) => line.startsWith(prefix))) {
        lines.add(line);
      }
    }
    return lines.join('\n').trim();
  }

  String _compactLibrarySnapshot(String snapshot) {
    final lines = <String>['COMPACT_LIBRARY_SNAPSHOT_V1'];
    var currentSection = '';
    var roleHintCount = 0;
    var instrumentCount = 0;
    var sampleFolderCount = 0;

    void ensureSection(String name) {
      currentSection = name;
      final header = '$name:';
      if (!lines.contains(header)) {
        lines.add(header);
      }
    }

    List<String> splitInlineEntries(String inner) {
      final entries = <String>[];
      final buffer = StringBuffer();
      var bracketDepth = 0;
      for (var i = 0; i < inner.length; i++) {
        final char = inner[i];
        if (char == '[') {
          bracketDepth++;
        } else if (char == ']' && bracketDepth > 0) {
          bracketDepth--;
        }
        if (char == ',' && bracketDepth == 0) {
          final item = buffer.toString().trim();
          if (item.isNotEmpty) entries.add(item);
          buffer.clear();
          continue;
        }
        buffer.write(char);
      }
      final item = buffer.toString().trim();
      if (item.isNotEmpty) entries.add(item);
      return entries;
    }

    void appendRoleHintEntries(String inner) {
      ensureSection('library_role_hints');
      for (final entry in splitInlineEntries(inner)) {
        if (roleHintCount >= 18) break;
        final equalsIndex = entry.indexOf('=');
        if (equalsIndex <= 0) continue;
        final role = entry.substring(0, equalsIndex).trim();
        final value = entry.substring(equalsIndex + 1).trim();
        if (role.isEmpty || value.isEmpty) continue;
        final roleName = role.startsWith('role:')
            ? role.substring('role:'.length)
            : role;
        final alias = role.startsWith('role:') ? role : 'role:$roleName';
        lines.add('- $roleName: alias=$alias examples=$value');
        roleHintCount++;
      }
    }

    void appendInstrumentEntries(String inner) {
      ensureSection('built_in_instruments');
      for (final entry in splitInlineEntries(inner)) {
        if (instrumentCount >= 18) break;
        final equalsIndex = entry.indexOf('=');
        final family =
            (equalsIndex <= 0 ? entry : entry.substring(0, equalsIndex)).trim();
        final value = equalsIndex <= 0
            ? ''
            : entry.substring(equalsIndex + 1).trim();
        if (family.isEmpty) continue;
        lines.add(value.isEmpty ? '- $family' : '- $family: $value');
        instrumentCount++;
      }
    }

    void appendAudioSampleEntries(String inner) {
      ensureSection('library_audio_samples');
      for (final entry in splitInlineEntries(inner)) {
        if (sampleFolderCount >= 12) break;
        final equalsIndex = entry.indexOf('=');
        final folder =
            (equalsIndex <= 0 ? entry : entry.substring(0, equalsIndex)).trim();
        final value = equalsIndex <= 0
            ? ''
            : entry.substring(equalsIndex + 1).trim();
        if (folder.isEmpty) continue;
        lines.add(value.isEmpty ? '- $folder' : '- $folder: $value');
        sampleFolderCount++;
      }
    }

    for (final raw in snapshot.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('library_role_hints:')) {
        final rest = line.substring('library_role_hints:'.length).trim();
        if (rest.isEmpty) {
          ensureSection('library_role_hints');
        } else {
          appendRoleHintEntries(rest);
        }
        continue;
      }
      if (line.startsWith('built_in_instruments:')) {
        final rest = line.substring('built_in_instruments:'.length).trim();
        if (rest.isEmpty) {
          ensureSection('built_in_instruments');
        } else {
          appendInstrumentEntries(rest);
        }
        continue;
      }
      if (line.startsWith('library_audio_samples:')) {
        final rest = line.substring('library_audio_samples:'.length).trim();
        if (rest.isEmpty) {
          ensureSection('library_audio_samples');
        } else {
          appendAudioSampleEntries(rest);
        }
        continue;
      }
      if (line.startsWith('library_role_hints{') && line.endsWith('}')) {
        final inner = line.substring(
          'library_role_hints{'.length,
          line.length - 1,
        );
        appendRoleHintEntries(inner);
        continue;
      }
      if (line.startsWith('instrument_hints{') && line.endsWith('}')) {
        ensureSection('built_in_instruments');
        final ids = <String>[];
        final inner = line.substring(
          'instrument_hints{'.length,
          line.length - 1,
        );
        for (final entry in splitInlineEntries(inner)) {
          final equalsIndex = entry.indexOf('=');
          final instrumentId =
              (equalsIndex <= 0 ? entry : entry.substring(0, equalsIndex))
                  .trim();
          if (instrumentId.isNotEmpty) ids.add(instrumentId);
        }
        if (ids.isNotEmpty && instrumentCount < 18) {
          lines.add('- Hints: [${ids.take(24).join(', ')}]');
          instrumentCount++;
        }
        continue;
      }
      if (line.endsWith(':') && !line.startsWith('- ')) {
        currentSection = line.substring(0, line.length - 1);
        if (const <String>{
          'built_in_instruments',
          'library_role_hints',
          'library_audio_samples',
        }.contains(currentSection)) {
          lines.add(line);
        }
        continue;
      }
      if (currentSection == 'built_in_instruments' && line.startsWith('- ')) {
        if (instrumentCount < 18) lines.add(line);
        instrumentCount++;
        continue;
      }
      if (currentSection == 'library_role_hints' && line.startsWith('- ')) {
        if (roleHintCount < 18) lines.add(line);
        roleHintCount++;
        continue;
      }
      if (currentSection == 'library_audio_samples' && line.startsWith('- ')) {
        if (sampleFolderCount < 12) lines.add(line);
        sampleFolderCount++;
      }
    }
    return lines.join('\n').trim();
  }

  _PackedContextSnapshots _packContextSnapshots({
    required String mode,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
  }) {
    if (mode != 'compact') {
      return _PackedContextSnapshots(
        projectSnapshot: projectSnapshot,
        selectionSnapshot: selectionSnapshot,
        librarySnapshot: librarySnapshot,
      );
    }
    final normalizedProject = projectSnapshot.trim();
    final normalizedSelection = selectionSnapshot.trim();
    final normalizedLibrary = librarySnapshot.trim();
    return _PackedContextSnapshots(
      projectSnapshot:
          normalizedProject.startsWith('COMPACT_PROJECT_SNAPSHOT_V1')
          ? projectSnapshot
          : _compactProjectSnapshot(projectSnapshot),
      selectionSnapshot: normalizedSelection.isEmpty
          ? ''
          : normalizedSelection.startsWith('COMPACT_SELECTION_SNAPSHOT_V1')
          ? selectionSnapshot
          : _compactSelectionSnapshot(selectionSnapshot),
      librarySnapshot: normalizedLibrary.isEmpty
          ? ''
          : normalizedLibrary.startsWith('COMPACT_LIBRARY_SNAPSHOT_V1')
          ? librarySnapshot
          : _compactLibrarySnapshot(librarySnapshot),
    );
  }

  Map<String, dynamic> _readClientPolicy(Map<String, dynamic> clientContext) {
    final policy = <String, dynamic>{};
    for (final key in <String>[
      'subscription_plan',
      'plugin_access',
      'row_creation_policy',
    ]) {
      final value = clientContext[key];
      if (value is String && value.trim().isNotEmpty) {
        final trimmed = value.trim();
        policy[key] = trimmed.length > 500
            ? trimmed.substring(0, 500)
            : trimmed;
      }
    }

    for (final key in <String>['max_rows', 'current_rows']) {
      final parsed = _readNonNegativeInt(clientContext[key]);
      if (parsed != null) policy[key] = parsed;
    }

    final allowedEffects = _readStringList(
      clientContext['allowed_builtin_effects'],
    );
    if (allowedEffects.isNotEmpty) {
      policy['allowed_builtin_effects'] = allowedEffects;
    }

    final allowedInstruments = _readStringList(
      clientContext['allowed_instrument_ids'],
    );
    if (allowedInstruments.isNotEmpty) {
      policy['allowed_instrument_ids'] = allowedInstruments;
    }

    return policy;
  }

  List<String> _clientPolicyPromptLines(Map<String, dynamic> clientPolicy) {
    if (clientPolicy.isEmpty) return const <String>[];
    final lines = <String>['', 'CLIENT ENTITLEMENT POLICY'];
    final subscriptionPlan =
        clientPolicy['subscription_plan']?.toString().trim() ?? '';
    final pluginAccess = clientPolicy['plugin_access']?.toString().trim() ?? '';
    final rowCreationPolicy =
        clientPolicy['row_creation_policy']?.toString().trim() ?? '';
    final maxRows = clientPolicy['max_rows'];
    final currentRows = clientPolicy['current_rows'];
    final allowedEffects = clientPolicy['allowed_builtin_effects'];
    final allowedInstruments = clientPolicy['allowed_instrument_ids'];

    if (subscriptionPlan.isNotEmpty) {
      lines.add('- Current subscription plan: $subscriptionPlan.');
    }
    if (maxRows is int) {
      var rowLine =
          '- Maximum project row_index is ${maxRows - 1}; do not emit actions targeting row_index >= $maxRows.';
      if (currentRows is int) {
        rowLine += ' Current row count is $currentRows.';
      }
      lines.add(rowLine);
    }
    if (rowCreationPolicy.isNotEmpty) {
      lines.add('- Row creation policy: $rowCreationPolicy');
    }
    if (pluginAccess.isNotEmpty) {
      lines.add('- Plugin access: $pluginAccess.');
    }
    if (allowedEffects is List && allowedEffects.isNotEmpty) {
      lines.add(
        '- Effect/plugin actions may only add or target these built-in effects unless the client explicitly allows all plugins: ${allowedEffects.join(', ')}.',
      );
    }
    if (allowedInstruments is List && allowedInstruments.isNotEmpty) {
      lines.add(
        '- New MIDI/instrument actions may only use instrument_id values present in LIBRARY_SNAPSHOT and in this allowed list: ${allowedInstruments.join(', ')}.',
      );
    }
    return lines;
  }

  String _buildDirectSystemPrompt(
    Set<String> clientCapabilities,
    Map<String, dynamic> clientPolicy,
  ) {
    final lines = <String>[
      _effectiveSystemPrompt,
      '',
      'CLIENT CAPABILITY OVERRIDES',
      '- LIBRARY_SNAPSHOT lists the packaged instrument IDs and packaged sample-library paths this client may use.',
      '- LIBRARY_SNAPSHOT may be compact: instruments may be grouped by category, and sample folders may appear as `Folder: [fileA, fileB]`. In that case the exact library_path is `Folder/fileName`.',
      '- LIBRARY_SNAPSHOT may include library_role_hints such as kick, snare, hat, clap, loop, bass, or fx. Use those semantic groups first when choosing packaged drum samples.',
      '- If a request can be satisfied using a packaged instrument ID or packaged sample path from LIBRARY_SNAPSHOT, do not treat it as unsupported generation.',
      ..._clientPolicyPromptLines(clientPolicy),
    ];
    if (clientCapabilities.contains('daw.project_edit.set_tempo')) {
      lines.add(
        '- This client supports project_edit set_tempo for direct BPM/project tempo changes. For requests like "make the song faster/slower", include time_stretch_audio=true and preserve_pitch=true so existing audio follows the new tempo. For grid/metronome-only BPM edits, omit or set time_stretch_audio=false.',
      );
    } else {
      lines.add('- This client does not support project_edit set_tempo.');
    }
    if (clientCapabilities.contains('daw.sample_insert.library')) {
      lines.add(
        '- This client supports sample_insert using exact library_path values or role aliases like role:kick from LIBRARY_SNAPSHOT. sample_insert creates audio clips; if the selected row is an instrument lane, target or create a nearby audio row instead of refusing.',
      );
    } else {
      lines.add(
        '- This client does not support AI sample/library insertion; do not emit sample_insert.',
      );
    }
    if (clientCapabilities.contains('daw.midi_compose.instrument_insert')) {
      lines.add(
        '- This client supports creating a new MIDI clip on a packaged built-in instrument by using midi_compose with instrument_id from LIBRARY_SNAPSHOT plus valid notes/progression.',
      );
    } else {
      lines.add(
        '- This client may only use midi_compose on an existing editable MIDI/instrument target.',
      );
    }
    if (clientCapabilities.contains('daw.clean_content_rows')) {
      lines.add(
        '- This client supports clean placement for newly added samples, loops, drums, keys, pads, bass, melodies, or generated parts: use placement_policy="clean_row" or prefer_clean_row=true on each sample item/MIDI action or target for broad additions that should move to empty/new rows. User placement wins: if the user asks for the current, selected, named, numbered, or otherwise particular row, target that row and set allow_layer_existing_row=true on that item/action or target.',
      );
    }
    if (clientCapabilities.contains('daw.midi_compose.transpose_notes')) {
      lines.add('- This client supports midi_compose transpose_notes.');
    } else {
      lines.add('- This client does not support midi_compose transpose_notes.');
    }
    if (clientCapabilities.contains('daw.midi_compose.audio_to_midi')) {
      lines.add(
        '- This client supports midi_compose convert_audio_to_midi for transcribing an existing project audio clip into a new MIDI clip below it.',
      );
    } else {
      lines.add(
        '- This client does not support audio-to-MIDI transcription; do not emit midi_compose convert_audio_to_midi.',
      );
    }
    if (clientCapabilities.contains('daw.clip_edit.pitch_shift')) {
      lines.add(
        '- This client supports direct audio clip/stem pitch and key changes. For audio clip or stem pitch/key changes, use daw_assistant_actions clip_edit operation pitch_shift with semitones or delta_semitones. Do not add a Pitch Shift effect or automation unless the user explicitly asks for an effect/automation. Treat "one key" as one semitone.',
      );
    } else {
      lines.add(
        '- This client does not support direct audio clip/stem pitch and key changes. Do not emit clip_edit pitch_shift. Do not add a Pitch Shift effect or automation unless the user explicitly asks for an effect/automation.',
      );
    }
    lines.add(
      '- For compound requests like "remove vocals and lower the pitch/key of the background/instrumental", emit both actions in one daw_assistant_actions call: first stem_separate vocal_instrumental on the source clip, then clip_edit pitch_shift on the instrumental/background stem. Target the second action with label_contains="Instrumental" when helpful. Do not tell the user to ask again for the second step.',
    );
    lines.add(
      '- When the user names an instrument or source, such as synth, piano, bass, drums, kick, snare, or vocal, target that identity over the currently selected clip if the selection appears to be a different source.',
    );
    return lines.join('\n').trim();
  }

  String _clientCapabilitySignature(Set<String> capabilities) {
    if (capabilities.isEmpty) return 'legacy';
    final sorted = capabilities.toList()..sort();
    return sorted.join(',');
  }

  String _stableJsonEncode(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_stableJsonEncode(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_stableJsonEncode).join(',')}]';
    }
    return jsonEncode(value);
  }

  String _clientPolicySignature(Map<String, dynamic> policy) {
    if (policy.isEmpty) return 'default_policy';
    return _stableJsonEncode(policy);
  }

  String _defaultReasoningEffort(String modelName) {
    final normalized = modelName.trim().toLowerCase();
    if (normalized.startsWith('gpt-5.4-mini')) {
      return 'low';
    }
    if (normalized.startsWith('gpt-5-pro') ||
        normalized.startsWith('gpt-5.2-pro') ||
        normalized.startsWith('gpt-5.4-pro')) {
      return 'high';
    }
    if (normalized.startsWith('gpt-5.4') ||
        normalized.startsWith('gpt-5.2') ||
        normalized.startsWith('gpt-5.1')) {
      return 'none';
    }
    if (normalized.startsWith('gpt-5')) {
      return 'minimal';
    }
    return '';
  }

  List<Map<String, dynamic>> _buildInputMessages({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    MixingResult? pendingMix,
  }) {
    return [
      {'role': 'user', 'content': 'PROJECT_SNAPSHOT:\n$projectSnapshot'},
      if (selectionSnapshot.trim().isNotEmpty)
        {'role': 'user', 'content': 'SELECTION_SNAPSHOT:\n$selectionSnapshot'},
      if (librarySnapshot.trim().isNotEmpty)
        {'role': 'user', 'content': 'LIBRARY_SNAPSHOT:\n$librarySnapshot'},
      if (pendingMix != null)
        {
          'role': 'user',
          'content':
              '''
              PENDING_MIX_PROPOSAL:
              ${jsonEncode(pendingMix.toJson())}

              A mix proposal was previously discussed in the chat at some point.
              You may refer to this if it is relevant to the discussion at this current point.
              If it is not relevant, please ignore this.
              ''',
        },
      ...conversation.map((m) => {'role': m['role'], 'content': m['content']}),
      {'role': 'user', 'content': userText},
    ];
  }

  Map<String, dynamic> _dawTargetSchema({bool allowMasterScope = false}) {
    final scopeValues = <String>[
      'selected',
      'all_audio',
      'all',
      'group',
      if (allowMasterScope) 'master',
    ];
    return <String, dynamic>{
      'type': 'object',
      'description':
          'Target reference for the DAW action. Use existing project context and selection to fill what you already know. Resolve relative references like top/bottom/first/last row or line into an explicit row_index when the intended row is clear, preferring occupied-row context over empty rows. Resolve natural identity references using labels, filenames, instrument names or IDs, clip kind, and row/source cues from the snapshots. Use prefer_selected only for explicit selection references such as "this one", "that one", "here", or "selected".',
      'properties': <String, dynamic>{
        'clip_index': {'type': 'integer', 'minimum': 0},
        'clip_indices': {
          'type': 'array',
          'items': {'type': 'integer', 'minimum': 0},
          'minItems': 1,
        },
        'row_index': {'type': 'integer', 'minimum': 0},
        'scope': {'type': 'string', 'enum': scopeValues},
        'group_id': {'type': 'string'},
        'group_name': {'type': 'string'},
        'prefer_selected': {
          'type': 'boolean',
          'description':
              'Use when the user refers to the current selection with phrases like "this one", "that one", or "here".',
        },
        'placement_policy': {
          'type': 'string',
          'enum': [
            'clean_row',
            'empty_row',
            'new_row',
            'separate_row',
            'existing_row',
            'layer_existing_row',
          ],
          'description':
              'Use clean_row/empty_row/new_row/separate_row for broad new musical parts. Use existing_row/layer_existing_row only when the user explicitly asks for a current, selected, named, numbered, or otherwise specific row.',
        },
        'prefer_clean_row': {
          'type': 'boolean',
          'description':
              'True when broad new content should avoid occupied source rows.',
        },
        'allow_layer_existing_row': {
          'type': 'boolean',
          'description':
              'True when the user explicitly asked to add to a specific row that may already contain clips.',
        },
        'automation_target_id': {'type': 'string'},
        'target_id': {'type': 'string'},
        'lane_id': {'type': 'string'},
        'effect_index': {'type': 'integer', 'minimum': 0},
        'effect_name': {'type': 'string'},
        'plugin_name': {'type': 'string'},
        'effect_name_contains': {'type': 'string'},
        'param_id': {'type': 'string'},
        'param_name': {'type': 'string'},
      },
      'additionalProperties': true,
    };
  }

  Map<String, dynamic> _midiNoteSchema() => <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'pitch': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 127,
        'description':
            'MIDI note number, for example 60 for middle C. Do not use note names like C4.',
      },
      'start_beat': {
        'type': 'number',
        'description':
            'Zero-based start beat in the clip. Measure 1 beat 1 is start_beat 0.',
      },
      'length_beats': {
        'type': 'number',
        'exclusiveMinimum': 0,
        'description': 'Note length in beats.',
      },
      'velocity': {
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'description':
            'Normalized velocity from 0 to 1. Do not use 1 to 127 velocity values.',
      },
    },
    'required': ['pitch', 'start_beat', 'length_beats'],
    'additionalProperties': true,
  };

  List<Map<String, dynamic>>
  _directOpenAiToolSchemas() => <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'function',
      'name': 'informational_response',
      'strict': false,
      'description':
          'Use for explanations, summaries, unsupported or unimplemented requests, empty-project replies, and any case where no valid executable action can be formed. Also use this when the user\'s main request depends on unsupported features and a nearby supported tool would be misleading.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'message': {
            'type': 'string',
            'description':
                'Short user-facing response. Also use this for unsupported or not-yet-implemented features.',
          },
          'cancels_pending': {
            'type': 'boolean',
            'description':
                'True only when the user clearly cancels or rejects a pending mix proposal.',
          },
        },
        'required': ['message', 'cancels_pending'],
        'additionalProperties': false,
      },
    },
    <String, dynamic>{
      'type': 'function',
      'name': 'daw_assistant_actions',
      'strict': false,
      'description':
          'Use for tutorials, project edits like BPM changes, row-group creation/folding, row color changes, library sample insertion or replacement, clip arrangement/editing, plugin CRUD, automation edits such as sidechain-like ducking, auto-pan, stereo movement, or filter sweeps, MIDI composition/editing, stem separation, and role override. For audio clip or stem pitch/key changes, use clip_edit pitch_shift with semitones or delta_semitones, not a Pitch Shift effect or automation, unless the user explicitly asks for an effect or automation. For group bus plugin or mix requests, target the existing group with scope=group plus group_id or group_name so the app edits the group bus, not each child row. Use row_group_edit only for creating, removing from, or folding/unfolding row groups. Use clip_edit glue for merge/consolidate/bounce-clip requests. For autotune, auto-tune, pitch correction, or Melodyne-style vocal tuning, add the built-in Pitch Corrector effect. For drum or beat-building requests using packaged samples, prefer action over explanation: choose semantically matching library files or advertised role aliases like role:kick, arrange them with musical spacing, and keep core roles like kick/snare/hats on separate rows when helpful. sample_insert creates audio clips; if selection is an instrument lane, target/create a nearby audio row instead of refusing. For 8+ bar starter grooves or build-ups, prefer a workable scaffold with repetition plus light variation or fills instead of one identical bar copied forever. If the user wants a placed sample swapped out, prefer replacing the targeted clips while preserving timing. Inspect existing plugin chains and selected MIDI note state when available: prefer modifying, unbypassing, extending, or reshaping what is already there when it is close, and remove conflicting effects or rewrite notes only when the current state clearly fights the user goal. Never use for pure sonic mix changes. Only emit actions the app can actually execute.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'assistant_message': {
            'type': 'string',
            'description':
                'Short user-facing message in the user language. Must match the emitted action type, must not be a placeholder, and must not switch languages unless the user did.',
          },
          'actions': {
            'type': 'array',
            'minItems': 1,
            'items': {
              'oneOf': [
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['project_edit'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['set_tempo'],
                        },
                        'tempo_bpm': {
                          'type': 'number',
                          'minimum': 20,
                          'maximum': 999,
                        },
                        'bpm': {
                          'type': 'number',
                          'minimum': 20,
                          'maximum': 999,
                        },
                        'time_stretch_audio': {
                          'type': 'boolean',
                          'description':
                              'True when the user asks to make the song/audio faster or slower. False for grid/metronome-only BPM edits.',
                        },
                        'preserve_pitch': {
                          'type': 'boolean',
                          'description':
                              'Use true by default for song-speed changes so pitch stays stable.',
                        },
                      },
                      'required': ['operation'],
                      'anyOf': [
                        {
                          'required': ['tempo_bpm'],
                        },
                        {
                          'required': ['bpm'],
                        },
                      ],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_mix'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': [
                            'set_gain',
                            'adjust_gain',
                            'set_pan',
                            'adjust_pan',
                          ],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'row_number': {'type': 'integer', 'minimum': 1},
                        'track_number': {'type': 'integer', 'minimum': 1},
                        'value': {'type': 'number'},
                        'gain': {'type': 'number'},
                        'gain_db': {'type': 'number'},
                        'db': {'type': 'number'},
                        'delta': {'type': 'number'},
                        'delta_db': {'type': 'number'},
                        'pan01': {'type': 'number', 'minimum': 0, 'maximum': 1},
                        'pan_signed': {
                          'type': 'number',
                          'minimum': -1,
                          'maximum': 1,
                        },
                        'direction': {
                          'type': 'string',
                          'enum': [
                            'up',
                            'down',
                            'left',
                            'right',
                            'center',
                            'hard_left',
                            'hard_right',
                          ],
                        },
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['transport_control'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': [
                            'play',
                            'pause',
                            'stop',
                            'restart',
                            'toggle_play_pause',
                            'start_recording',
                            'stop_recording',
                            'toggle_recording',
                            'undo',
                            'redo',
                            'enable_metronome',
                            'disable_metronome',
                            'toggle_metronome',
                            'enable_loop',
                            'disable_loop',
                            'toggle_loop',
                          ],
                        },
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_create'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['create'],
                        },
                        'position': {
                          'type': 'string',
                          'enum': ['end', 'above', 'below'],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'row_number': {'type': 'integer', 'minimum': 1},
                        'track_number': {'type': 'integer', 'minimum': 1},
                        'name': {
                          'type': 'string',
                          'minLength': 1,
                          'maxLength': 80,
                        },
                        'new_name': {
                          'type': 'string',
                          'minLength': 1,
                          'maxLength': 80,
                        },
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_delete'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['delete'],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'row_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'track_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_rename'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['rename'],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'name': {
                          'type': 'string',
                          'minLength': 1,
                          'maxLength': 80,
                        },
                        'new_name': {
                          'type': 'string',
                          'minLength': 1,
                          'maxLength': 80,
                        },
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_mute'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['mute', 'unmute', 'toggle'],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'row_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'track_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'group_id': {'type': 'string'},
                        'group_name': {'type': 'string'},
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_solo'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['solo', 'unsolo', 'toggle'],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'row_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'track_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'group_id': {'type': 'string'},
                        'group_name': {'type': 'string'},
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_select'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['select'],
                        },
                        'target': _dawTargetSchema(),
                        'row_index': {'type': 'integer', 'minimum': 0},
                        'row_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'track_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_color_edit'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['set', 'clear'],
                        },
                        'target': _dawTargetSchema(),
                        'row_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'track_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'color': {'type': 'integer', 'minimum': 0},
                        'argb': {'type': 'integer', 'minimum': 0},
                        'color_name': {'type': 'string'},
                        'group_id': {'type': 'string'},
                        'group_name': {'type': 'string'},
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['row_group_edit'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['create', 'remove_row', 'toggle_collapsed'],
                        },
                        'target': _dawTargetSchema(),
                        'row_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'track_indices': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'rows': {
                          'type': 'array',
                          'items': {'type': 'integer', 'minimum': 0},
                          'minItems': 1,
                        },
                        'group_id': {'type': 'string'},
                        'group_name': {'type': 'string'},
                        'name': {'type': 'string'},
                        'color': {'type': 'integer', 'minimum': 0},
                      },
                      'required': ['operation'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['audio_enhance'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['phone_mic_cleanup'],
                        },
                        'target': _dawTargetSchema(),
                      },
                      'required': ['operation', 'target'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['sample_insert'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['insert_audio_clips', 'replace_audio_clips'],
                        },
                        'items': {
                          'type': 'array',
                          'minItems': 1,
                          'items': {
                            'type': 'object',
                            'properties': {
                              'library_path': {'type': 'string'},
                              'target': _dawTargetSchema(),
                              'row_index': {'type': 'integer', 'minimum': 0},
                              'start_ms': {'type': 'number'},
                              'start_measure': {'type': 'number'},
                              'start_beat': {'type': 'number'},
                              'repeat_count': {'type': 'integer', 'minimum': 1},
                              'length_ms': {'type': 'number'},
                              'length_measures': {'type': 'number'},
                              'length_beats': {'type': 'number'},
                              'until_ms': {'type': 'number'},
                              'until_measure': {'type': 'number'},
                              'until_beat': {'type': 'number'},
                              'step_ms': {'type': 'number'},
                              'step_measures': {'type': 'number'},
                              'step_beats': {'type': 'number'},
                              'delta_rows': {'type': 'integer'},
                            },
                            'required': ['library_path'],
                            'additionalProperties': true,
                          },
                        },
                      },
                      'required': ['operation', 'items'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['tutorial'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'topic': {'type': 'string'},
                        'steps': {
                          'type': 'array',
                          'minItems': 1,
                          'items': {
                            'type': 'object',
                            'properties': {
                              'text': {'type': 'string'},
                              'target_id': {'type': 'string'},
                            },
                            'required': ['text'],
                            'additionalProperties': true,
                          },
                        },
                      },
                      'anyOf': [
                        {
                          'required': ['topic'],
                        },
                        {
                          'required': ['steps'],
                        },
                      ],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['clarify'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'question': {'type': 'string'},
                        'options': {
                          'type': 'array',
                          'items': {'type': 'string'},
                          'minItems': 2,
                        },
                      },
                      'required': ['question', 'options'],
                      'additionalProperties': false,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['clip_edit'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': [
                            'trim',
                            'auto_trim',
                            'cut',
                            'stretch',
                            'pitch_shift',
                            'glue',
                            'move',
                            'tempo_follow',
                            'auto_bpm_align',
                            'align_first_sound',
                            'tempo_detect_set_project',
                            'duplicate',
                            'delete',
                            'dialog_cleanup',
                            'dialog_remove_range',
                            'dialog_tighten_pauses',
                            'dialog_lift_quiet',
                          ],
                        },
                        'target': _dawTargetSchema(),
                        'trim_side': {
                          'type': 'string',
                          'enum': ['start', 'end'],
                        },
                        'new_start_ms': {'type': 'number'},
                        'target_ms': {'type': 'number'},
                        'align_to_ms': {'type': 'number'},
                        'first_sound_target_ms': {'type': 'number'},
                        'align_to': {
                          'type': 'string',
                          'enum': [
                            'playhead',
                            'nearest_beat',
                            'nearest_bar',
                            'bar',
                            'beat',
                            'project_start',
                            'clip_start',
                          ],
                        },
                        'bar_index': {'type': 'number'},
                        'beat_index': {'type': 'number'},
                        'paste_start_ms': {'type': 'number'},
                        'delta_ms': {'type': 'number'},
                        'new_start_measure': {'type': 'number'},
                        'paste_start_measure': {'type': 'number'},
                        'delta_measures': {'type': 'number'},
                        'step_ms': {'type': 'number'},
                        'step_measures': {'type': 'number'},
                        'step_beats': {'type': 'number'},
                        'repeat_count': {'type': 'integer', 'minimum': 1},
                        'length_ms': {'type': 'number'},
                        'length_measures': {'type': 'number'},
                        'length_beats': {'type': 'number'},
                        'semitones': {'type': 'number'},
                        'delta_semitones': {'type': 'number'},
                        'pitch_semitones': {'type': 'number'},
                        'new_pitch_semitones': {'type': 'number'},
                        'mode': {
                          'type': 'string',
                          'enum': ['set', 'delta'],
                        },
                        'until_ms': {'type': 'number'},
                        'until_measure': {'type': 'number'},
                        'until_beat': {'type': 'number'},
                        'direction': {
                          'type': 'string',
                          'enum': ['left', 'right', 'up', 'down'],
                        },
                        'new_row_index': {'type': 'integer', 'minimum': 0},
                        'timeline_duration_ms': {'type': 'number'},
                        'duration_ms': {'type': 'number'},
                        'beats_per_bar': {'type': 'number'},
                        'from_ms': {'type': 'number'},
                        'to_ms': {'type': 'number'},
                        'ranges': {
                          'type': 'array',
                          'items': {
                            'type': 'object',
                            'properties': {
                              'from_ms': {'type': 'number'},
                              'to_ms': {'type': 'number'},
                            },
                            'required': ['from_ms', 'to_ms'],
                            'additionalProperties': false,
                          },
                        },
                        'max_edits': {'type': 'integer', 'minimum': 1},
                        'boost_db': {'type': 'number'},
                        'max_gain': {'type': 'number'},
                        'min_quiet_ms': {'type': 'number'},
                        'min_pause_ms': {'type': 'number'},
                        'keep_pause_ms': {'type': 'number'},
                      },
                      'required': ['operation', 'target'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['effect_edit'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': [
                            'add',
                            'remove',
                            'bypass',
                            'unbypass',
                            'toggle_bypass',
                          ],
                        },
                        'target': _dawTargetSchema(allowMasterScope: true),
                      },
                      'required': ['operation', 'target'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['automation_edit'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': [
                            'set_points',
                            'add_ramp',
                            'clear',
                            'apply_template',
                          ],
                        },
                        'target': _dawTargetSchema(),
                        'template': {'type': 'string'},
                        'points': {
                          'type': 'array',
                          'minItems': 1,
                          'items': {
                            'type': 'object',
                            'properties': {
                              'time_ms': {'type': 'number'},
                              'value': {'type': 'number'},
                            },
                            'required': ['time_ms', 'value'],
                            'additionalProperties': true,
                          },
                        },
                        'start_ms': {'type': 'number'},
                        'length_ms': {'type': 'number'},
                        'delta_ms': {'type': 'number'},
                        'source_clip_index': {'type': 'integer', 'minimum': 0},
                        'source_row_index': {'type': 'integer', 'minimum': 0},
                        'source_role': {'type': 'string'},
                        'min_spacing_ms': {'type': 'number'},
                        'duck_value': {'type': 'number'},
                        'recover_value': {'type': 'number'},
                        'direction': {
                          'type': 'string',
                          'enum': ['left', 'right'],
                        },
                        'from_ms': {'type': 'number'},
                        'to_ms': {'type': 'number'},
                        'start_value': {'type': 'number'},
                        'end_value': {'type': 'number'},
                        'value_mode': {
                          'type': 'string',
                          'enum': ['normalized', 'real'],
                        },
                      },
                      'required': ['operation', 'target'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['midi_compose'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': [
                            'create_clip',
                            'compose_bassline',
                            'compose_pattern',
                            'replace_notes',
                            'append_notes',
                            'transpose_notes',
                            'convert_audio_to_midi',
                          ],
                        },
                        'target': _dawTargetSchema(),
                        'notes': {
                          'type': 'array',
                          'minItems': 1,
                          'items': _midiNoteSchema(),
                        },
                        'progression': {
                          'oneOf': [
                            {
                              'type': 'array',
                              'items': {'type': 'string'},
                              'minItems': 1,
                            },
                            {'type': 'string'},
                          ],
                        },
                        'beats_per_chord': {'type': 'number'},
                        'notes_per_chord': {'type': 'integer', 'minimum': 1},
                        'octave': {'type': 'integer'},
                        'semitones': {'type': 'number'},
                        'octaves': {'type': 'number'},
                        'instrument_id': {
                          'type': 'string',
                          'description':
                              'Built-in instrument id from LIBRARY_SNAPSHOT, for example mixroom.sub_bass or mixroom.air_pluck. Use this when creating a new MIDI clip on a packaged instrument. For generic harmony, chord, or piano MIDI requests with no specified instrument, prefer sfz.vsco.upright_piano when it is available in LIBRARY_SNAPSHOT.',
                        },
                        'instrument_name': {'type': 'string'},
                        'start_ms': {'type': 'number'},
                        'create_new_clip': {'type': 'boolean'},
                        'preserve_existing_notes': {'type': 'boolean'},
                      },
                      'required': ['operation', 'target'],
                      'anyOf': [
                        {
                          'required': ['notes'],
                        },
                        {
                          'required': ['progression'],
                        },
                        {
                          'properties': {
                            'operation': {'const': 'transpose_notes'},
                          },
                          'required': ['semitones'],
                        },
                        {
                          'properties': {
                            'operation': {'const': 'transpose_notes'},
                          },
                          'required': ['octaves'],
                        },
                        {
                          'properties': {
                            'operation': {'const': 'convert_audio_to_midi'},
                          },
                        },
                        {
                          'properties': {
                            'operation': {
                              'enum': ['replace_notes', 'append_notes'],
                            },
                            'preserve_existing_notes': {'const': true},
                          },
                          'anyOf': [
                            {
                              'required': ['length_measures'],
                            },
                            {
                              'required': ['length_beats'],
                            },
                          ],
                        },
                      ],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['midi_compose'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['chop_notes'],
                        },
                        'target': _dawTargetSchema(),
                        'subdivision': {'type': 'integer', 'minimum': 1},
                        'velocity_decay_per_slice': {'type': 'number'},
                        'velocity_jitter': {'type': 'number'},
                        'velocity_floor': {'type': 'number'},
                      },
                      'required': ['operation', 'target', 'subdivision'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['stem_separate'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['vocal_instrumental'],
                        },
                        'target': _dawTargetSchema(),
                      },
                      'required': ['operation', 'target'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['role_override'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['set'],
                        },
                        'target': _dawTargetSchema(),
                        'role': {
                          'type': 'string',
                          'enum': [
                            'vocals',
                            'drums',
                            'bass',
                            'guitar',
                            'synth',
                            'other',
                          ],
                        },
                      },
                      'required': ['operation', 'target', 'role'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
                {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['role_override'],
                    },
                    'data': {
                      'type': 'object',
                      'properties': {
                        'operation': {
                          'type': 'string',
                          'enum': ['clear'],
                        },
                        'target': _dawTargetSchema(),
                      },
                      'required': ['operation', 'target'],
                      'additionalProperties': true,
                    },
                  },
                  'required': ['type', 'data'],
                  'additionalProperties': false,
                },
              ],
            },
          },
        },
        'required': ['assistant_message', 'actions'],
        'additionalProperties': false,
      },
    },
    <String, dynamic>{
      'type': 'function',
      'name': 'mix_model_request',
      'strict': false,
      'description':
          'Use only for sonic mix changes on existing project material. Never use for clip movement, plugin CRUD, automation edits, MIDI writing, tutorials, stem separation, or unsupported features. Use reset_fx only for true reset/remix cases or when the current chain clearly conflicts with the requested broad vibe.',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'mode': {
            'type': 'string',
            'enum': ['execute', 'propose'],
            'description':
                'Use execute for clear actionable mix changes. Use propose only for alternative approaches that need approval.',
          },
          'assistant_message': {
            'type': 'string',
            'description':
                'Single short user-facing message describing the overall mix action in the user language.',
          },
          'asks_permission': {'type': 'boolean'},
          'actions': {
            'type': 'array',
            'minItems': 1,
            'description': 'One or more mix actions to apply.',
            'items': {
              'type': 'object',
              'properties': {
                'goal': {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['mix_request'],
                      'description':
                          'Always mix_request. Put the sonic intent in intents[].kind.',
                    },
                    'intents': {
                      'type': 'array',
                      'minItems': 1,
                      'items': {
                        'type': 'object',
                        'properties': {
                          'kind': {
                            'type': 'string',
                            'enum': [
                              'gain',
                              'pan',
                              'eq',
                              'reverb',
                              'delay',
                              'distortion',
                              'deesser',
                              'compressor',
                              'limiter',
                              'clipper',
                              'balance',
                            ],
                          },
                          'direction': {
                            'type': 'string',
                            'enum': [
                              'up',
                              'down',
                              'left',
                              'right',
                              'center',
                              'widen',
                              'narrow',
                              'remove',
                              'null',
                            ],
                          },
                          'descriptor': {
                            'type': 'string',
                            'enum': [
                              'mud_cut',
                              'box_cut',
                              'boom_cut',
                              'harsh_cut',
                              'presence_boost',
                              'air_boost',
                              'warmth_boost',
                              'thin_fix',
                              'dull_fix',
                              'low_cut',
                              'high_cut',
                              'null',
                            ],
                          },
                          'confidence': {'type': 'number'},
                        },
                        'required': ['kind', 'confidence'],
                      },
                    },
                    'target': {
                      'type': 'object',
                      'oneOf': [
                        {
                          'properties': {
                            'scope': {
                              'type': 'string',
                              'enum': ['master'],
                            },
                            'confidence': {'type': 'number'},
                          },
                          'required': ['scope', 'confidence'],
                          'additionalProperties': false,
                        },
                        {
                          'properties': {
                            'role': {'type': 'string'},
                            'row_index': {'type': 'integer', 'minimum': 0},
                            'group_id': {'type': 'string'},
                            'group_name': {'type': 'string'},
                            'scope': {
                              'type': 'string',
                              'enum': ['auto', 'row', 'group'],
                            },
                            'confidence': {'type': 'number'},
                          },
                          'required': ['scope', 'confidence'],
                          'additionalProperties': false,
                        },
                      ],
                    },
                    'intensity': {'type': 'number'},
                    'execution_profile': {
                      'type': 'string',
                      'enum': [
                        'producer_safe',
                        'creative_bold',
                        'experimental_extreme',
                      ],
                      'description':
                          'How conservative or stylized the mix lane should be. producer_safe = tasteful standard mix decisions, creative_bold = obvious/stylized but still musical, experimental_extreme = intentionally exaggerated or destructive.',
                    },
                    'audibility': {
                      'type': 'string',
                      'enum': ['subtle', 'noticeable', 'obvious', 'extreme'],
                      'description':
                          'How audible the result should feel to the user, independent of the intent kind.',
                    },
                    'reference_target': {
                      'type': 'object',
                      'oneOf': [
                        {
                          'properties': {
                            'row_index': {'type': 'integer', 'minimum': 0},
                            'confidence': {'type': 'number'},
                          },
                          'required': ['row_index', 'confidence'],
                          'additionalProperties': false,
                        },
                        {
                          'properties': {
                            'prefer_selected': {
                              'type': 'boolean',
                              'enum': [true],
                            },
                            'confidence': {'type': 'number'},
                          },
                          'required': ['prefer_selected', 'confidence'],
                          'additionalProperties': false,
                        },
                      ],
                      'description':
                          'Optional in-project reference row for mix matching. Use row_index when clear from PROJECT_SNAPSHOT, especially when labels, filenames, coverage, source_type, or reference cues make one row obviously reference-like. Use prefer_selected when the reference track is currently selected.',
                    },
                    'reference_mode': {
                      'type': 'string',
                      'enum': ['tone', 'loudness', 'width', 'glue', 'full_mix'],
                      'description':
                          'Which dimensions of the in-project reference to match. full_mix means broad tone+loudness+width+glue matching.',
                    },
                    'reference_closeness': {
                      'type': 'string',
                      'enum': ['loose', 'balanced', 'close'],
                      'description':
                          'How tightly to chase the in-project reference profile.',
                    },
                    'reset_fx': {
                      'type': 'boolean',
                      'description':
                          'Set true only when a reset/remix or clean rebuild is clearly preferable to tweaking the current chain. Leave false for ordinary incremental mix moves.',
                    },
                  },
                  'required': [
                    'type',
                    'intents',
                    'target',
                    'intensity',
                    'execution_profile',
                    'audibility',
                  ],
                },
              },
              'required': ['goal'],
            },
          },
        },
        'required': ['mode', 'assistant_message', 'actions'],
        'additionalProperties': false,
      },
    },
  ];

  Set<String> _intentToolNames(String userText, String toolRoutingMode) {
    if (toolRoutingMode != 'intent_scoped') {
      return <String>{
        'informational_response',
        'daw_assistant_actions',
        'mix_model_request',
      };
    }
    final text = userText.trim().toLowerCase();
    final starterCreation =
        RegExp(r'\b(lofi|lo-fi)\b').hasMatch(text) &&
        RegExp(
          r'\b(make|create|generate|write|compose|build)\b',
        ).hasMatch(text) &&
        RegExp(
          r'\b(song|beat|track|instrumental|starter|idea|loop)\b',
        ).hasMatch(text) &&
        !text.contains('remix');
    if (starterCreation) {
      return <String>{'informational_response', 'daw_assistant_actions'};
    }
    var hasMix = _mixIntentRe.hasMatch(text);
    var hasDaw = _dawIntentRe.hasMatch(text);
    final wantsInfo = _questionIntentRe.hasMatch(text);
    if (const <String>[
      'remix',
      'lofi',
      'lo-fi',
      'vibe',
      'style',
    ].any(text.contains)) {
      hasMix = true;
      hasDaw = true;
    }
    if (hasMix && hasDaw) {
      return <String>{
        'informational_response',
        'daw_assistant_actions',
        'mix_model_request',
      };
    }
    if (hasMix) return <String>{'informational_response', 'mix_model_request'};
    if (hasDaw) {
      return <String>{'informational_response', 'daw_assistant_actions'};
    }
    if (wantsInfo) return <String>{'informational_response'};
    return <String>{
      'informational_response',
      'daw_assistant_actions',
      'mix_model_request',
    };
  }

  bool _negatesStemSeparation(String text) {
    return RegExp(
          r"\b(do\s+not|don't|dont|stop|no\s+more|without)\b[^.?!]{0,96}\b(split|stem|stems|separat)",
        ).hasMatch(text) ||
        RegExp(
          r'\b(split|stem|stems|separat)[^.?!]{0,96}\b(no\s+more|anymore|again)\b',
        ).hasMatch(text);
  }

  List<String> _intentDawActionTypes({
    required List<String> allowedActionTypes,
    required String userText,
    required String toolRoutingMode,
  }) {
    if (toolRoutingMode != 'intent_scoped') return allowedActionTypes;
    final text = userText.toLowerCase();
    final selected = <String>{'tutorial', 'clarify'};
    final negatesStem = _negatesStemSeparation(text);

    void addIfAllowed(List<String> values) {
      for (final value in values) {
        if (allowedActionTypes.contains(value)) selected.add(value);
      }
    }

    if (RegExp(r'\b(mute|unmute|silence|unsilence)\b').hasMatch(text)) {
      addIfAllowed(<String>['row_mute', 'row_mix']);
    }
    if (RegExp(r'\b(solo|unsolo|isolate)\b').hasMatch(text)) {
      addIfAllowed(<String>['row_solo']);
    }
    if (RegExp(r'\b(rename|call|label)\b').hasMatch(text)) {
      addIfAllowed(<String>['row_rename', 'role_override']);
    }
    if (RegExp(r'\b(select|focus|active)\b').hasMatch(text)) {
      addIfAllowed(<String>['row_select']);
    }
    if (RegExp(r'\b(delete|remove|trash)\b').hasMatch(text)) {
      addIfAllowed(<String>['clip_edit', 'row_delete']);
    }
    if (RegExp(
      r'\b(play|pause|stop|restart|beginning|record|undo|redo|metronome|click|loop)\b',
    ).hasMatch(text)) {
      addIfAllowed(<String>['transport_control']);
    }
    if (!negatesStem &&
        RegExp(
          r'\b(split|stem|stems|separate|vocal|instrumental)\b',
        ).hasMatch(text)) {
      addIfAllowed(<String>['stem_separate']);
    }
    if (RegExp(r'\b(pitch|transpose|semitone|octave)\b').hasMatch(text)) {
      addIfAllowed(<String>['clip_edit', 'midi_compose']);
    }
    if (RegExp(r'\b(tempo|bpm|faster|slower)\b').hasMatch(text)) {
      addIfAllowed(<String>['project_edit']);
    }
    const levelTargetPattern =
        r'(?:vocal|voice|track|row|stem|pad|pads|bass|808|sub|drum|drums|kick|snare|hat|hats|guitar|piano|keys|synth|lead|instrumental)';
    final pitchDirectionRequest = RegExp(
      r'\b(pitch|transpose|octave|semitone|semitones|key)\b',
    ).hasMatch(text);
    final concreteLevelChangeRequest =
        !pitchDirectionRequest &&
        (RegExp(
              r'\b(volume|gain|level|fader|db|louder|quieter|turn up|turn down)\b',
            ).hasMatch(text) ||
            RegExp(
              r'\b(turn|bring|pull|push|take|make)\b[^.?!]{0,64}\b' +
                  levelTargetPattern +
                  r'\b[^.?!]{0,32}\b(up|down|lower|louder|quieter)\b',
            ).hasMatch(text) ||
            RegExp(
              r'\b' +
                  levelTargetPattern +
                  r'\b[^.?!]{0,64}\b(up|down|lower|louder|quieter|reduc|tuck)\b',
            ).hasMatch(text) ||
            RegExp(
              r'\b(lower|reduce|tuck)\b[^.?!]{0,48}\b' +
                  levelTargetPattern +
                  r'\b',
            ).hasMatch(text));
    if (RegExp(
          r'\b(add|insert|put|place|create|write|compose|generate|drum|kick|snare|hat|loop|sample|midi|instrument|keys|pad|bassline|melody|texture|vinyl|noise|riser|whoosh|fx|808|drop)\b',
        ).hasMatch(text) &&
        !concreteLevelChangeRequest) {
      addIfAllowed(<String>['sample_insert', 'midi_compose', 'row_create']);
    }
    if (RegExp(r'\b(pan|left|right|center)\b').hasMatch(text) ||
        concreteLevelChangeRequest) {
      addIfAllowed(<String>['row_mix']);
    }
    if (concreteLevelChangeRequest &&
        RegExp(
          r'\b(hook|chorus|verse|bridge|during|whenever|when|over time)\b',
        ).hasMatch(text)) {
      addIfAllowed(<String>['automation_edit', 'row_mix']);
    }
    if (RegExp(
      r'\b(remove|delete|take out|bypass|unbypass|toggle)\b[^.?!]{0,64}\b(effect|plugin|fx|distortion|compressor|compress|eq|reverb|delay|limiter|pitch corrector)\b',
    ).hasMatch(text)) {
      addIfAllowed(<String>['effect_edit']);
    }
    if (RegExp(
      r'\b(effect|plugin|fx|distortion|compressor|compress|eq|reverb|delay|limiter|pitch corrector)\b',
    ).hasMatch(text)) {
      addIfAllowed(<String>['effect_edit']);
    }
    if (RegExp(
      r'\b(automation|duck|ducking|sidechain|pump|pumping|sweep|fade)\b',
    ).hasMatch(text)) {
      addIfAllowed(<String>['automation_edit']);
    }
    if (RegExp(
      r'\b(move|copy|duplicate|trim|cut|glue|adlib|chorus clip)\b',
    ).hasMatch(text)) {
      addIfAllowed(<String>['clip_edit']);
    }
    if (RegExp(
      r'\b(clean|cleanup|noise|quiet noise|dialog cleanup|phone mic)\b',
    ).hasMatch(text)) {
      addIfAllowed(<String>['audio_enhance', 'clip_edit']);
    }
    if (RegExp(r'\b(color)\b').hasMatch(text)) {
      addIfAllowed(<String>['row_color_edit']);
    }
    if (RegExp(r'\b(group)\b').hasMatch(text)) {
      addIfAllowed(<String>['row_group_edit']);
    }
    if (RegExp(r'\b(role)\b').hasMatch(text)) {
      addIfAllowed(<String>['role_override']);
    }
    if (const <String>[
      'remix',
      'lofi',
      'lo-fi',
      'vibe',
      'style',
    ].any(text.contains)) {
      addIfAllowed(<String>[
        'sample_insert',
        'midi_compose',
        'clip_edit',
        'row_mix',
        'project_edit',
      ]);
    }
    final scoped = allowedActionTypes
        .where((value) => selected.contains(value))
        .toList(growable: false);
    final result = scoped.length > 2 ? scoped : allowedActionTypes;
    if (!negatesStem) return result;
    return result.where((value) => value != 'stem_separate').toList();
  }

  void _filterDirectToolSchemas(
    List<Map<String, dynamic>> tools,
    Set<String> clientCapabilities,
  ) {
    final allowedActionTypes = <String>{
      'tutorial',
      'clarify',
      'clip_edit',
      'effect_edit',
      'row_group_edit',
      'row_color_edit',
      'automation_edit',
      'midi_compose',
      'stem_separate',
      'role_override',
      'audio_enhance',
      if (clientCapabilities.contains('daw.transport_control'))
        'transport_control',
      if (clientCapabilities.contains('daw.row_mute')) 'row_mute',
      if (clientCapabilities.contains('daw.row_solo')) 'row_solo',
      if (clientCapabilities.contains('daw.row_rename')) 'row_rename',
      if (clientCapabilities.contains('daw.row_select')) 'row_select',
      if (clientCapabilities.contains('daw.row_delete')) 'row_delete',
      if (clientCapabilities.contains('daw.row_create')) 'row_create',
      if (clientCapabilities.contains('daw.row_mix')) 'row_mix',
      if (clientCapabilities.contains('daw.project_edit.set_tempo'))
        'project_edit',
      if (clientCapabilities.contains('daw.sample_insert.library'))
        'sample_insert',
    };

    for (final tool in tools) {
      if (tool['name'] != 'daw_assistant_actions') continue;
      final parameters = tool['parameters'];
      if (parameters is! Map) continue;
      final properties = parameters['properties'];
      if (properties is! Map) continue;
      final actions = properties['actions'];
      if (actions is! Map) continue;
      final items = actions['items'];
      if (items is! Map) continue;

      final itemProperties = items['properties'];
      if (itemProperties is Map) {
        final typeSchema = itemProperties['type'];
        if (typeSchema is Map) {
          typeSchema['enum'] = allowedActionTypes.toList(growable: false);
          return;
        }
      }

      final variants = items['oneOf'];
      if (variants is! List) continue;
      final removedVariants = <dynamic>[];
      for (final variant in variants) {
        if (variant is! Map) {
          removedVariants.add(variant);
          continue;
        }
        final variantProperties = variant['properties'];
        if (variantProperties is! Map) {
          removedVariants.add(variant);
          continue;
        }
        final typeSchema = variantProperties['type'];
        if (typeSchema is! Map) {
          removedVariants.add(variant);
          continue;
        }
        final allowedValues = <String>{};
        final rawEnum = typeSchema['enum'];
        if (rawEnum is List) {
          allowedValues.addAll(
            rawEnum
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty),
          );
        }
        final rawConst = typeSchema['const'];
        if (rawConst != null) {
          final normalizedConst = rawConst.toString().trim();
          if (normalizedConst.isNotEmpty) allowedValues.add(normalizedConst);
        }
        if (!allowedValues.any(allowedActionTypes.contains)) {
          removedVariants.add(variant);
        }
      }
      for (final variant in removedVariants) {
        variants.remove(variant);
      }
      return;
    }
  }

  void _filterDirectToolSchemasForIntent(
    List<Map<String, dynamic>> tools, {
    required String userText,
    required String toolRoutingMode,
  }) {
    if (toolRoutingMode != 'intent_scoped') return;
    final allowedToolNames = _intentToolNames(userText, toolRoutingMode);
    tools.removeWhere(
      (tool) => !allowedToolNames.contains(tool['name']?.toString().trim()),
    );

    for (final tool in tools) {
      if (tool['name'] != 'daw_assistant_actions') continue;
      final parameters = tool['parameters'];
      if (parameters is! Map) continue;
      final properties = parameters['properties'];
      if (properties is! Map) continue;
      final actions = properties['actions'];
      if (actions is! Map) continue;
      final items = actions['items'];
      if (items is! Map) continue;

      final itemProperties = items['properties'];
      if (itemProperties is Map) {
        final typeSchema = itemProperties['type'];
        if (typeSchema is Map) {
          final rawEnum = typeSchema['enum'];
          if (rawEnum is List) {
            final currentTypes = rawEnum
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false);
            typeSchema['enum'] = _intentDawActionTypes(
              allowedActionTypes: currentTypes,
              userText: userText,
              toolRoutingMode: toolRoutingMode,
            );
          }
          return;
        }
      }

      final variants = items['oneOf'];
      if (variants is! List) continue;
      final variantTypes = <Object, Set<String>>{};
      final currentTypes = <String>[];
      for (final variant in variants) {
        if (variant is! Map) continue;
        final variantProperties = variant['properties'];
        if (variantProperties is! Map) continue;
        final typeSchema = variantProperties['type'];
        if (typeSchema is! Map) continue;
        final allowedValues = <String>{};
        final rawEnum = typeSchema['enum'];
        if (rawEnum is List) {
          allowedValues.addAll(
            rawEnum
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty),
          );
        }
        final rawConst = typeSchema['const'];
        if (rawConst != null) {
          final normalizedConst = rawConst.toString().trim();
          if (normalizedConst.isNotEmpty) allowedValues.add(normalizedConst);
        }
        if (allowedValues.isEmpty) continue;
        variantTypes[variant] = allowedValues;
        for (final value in allowedValues) {
          if (!currentTypes.contains(value)) currentTypes.add(value);
        }
      }
      final scopedTypes = _intentDawActionTypes(
        allowedActionTypes: currentTypes,
        userText: userText,
        toolRoutingMode: toolRoutingMode,
      ).toSet();
      variants.removeWhere((variant) {
        final allowedValues = variantTypes[variant];
        if (allowedValues == null) return false;
        return !allowedValues.any(scopedTypes.contains);
      });
      return;
    }
  }

  String _conversationSeedHash(String seedInstructions) => crypto.sha256
      .convert(utf8.encode(seedInstructions.trim()))
      .toString()
      .substring(0, 16);

  String _buildDirectSeedInstructions({
    required Set<String> clientCapabilities,
    required Map<String, dynamic> clientPolicy,
    required String instructionOverlay,
  }) {
    return <String>[
      _buildDirectSystemPrompt(clientCapabilities, clientPolicy),
      if (instructionOverlay.trim().isNotEmpty) instructionOverlay.trim(),
    ].join('\n\n').trim();
  }

  List<Map<String, dynamic>> _buildOpenAiConversationSeedItems({
    required String seedInstructions,
  }) {
    final normalizedSeed = seedInstructions.trim();
    if (normalizedSeed.isEmpty) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'message',
        'role': 'developer',
        'content': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'input_text',
            'text': <String>[
              'MIXROOM SEEDED BEHAVIOR CONTRACT',
              'These persistent instructions apply to this OpenAI Conversation unless a later request-local instruction explicitly overrides them.',
              '',
              normalizedSeed,
            ].join('\n'),
          },
        ],
      },
    ];
  }

  String _buildSeededConversationRequestInstructions({
    required String seedHash,
    required String contextInstructions,
  }) {
    return <String>[
      'SEEDED MIXROOM CONTRACT ACTIVE',
      '- The OpenAI conversation already contains the full Mixroom behavior contract seed_hash=$seedHash.',
      '- The seeded contract includes CLIENT ENTITLEMENT POLICY and client capability overrides for this runtime fingerprint.',
      '- Current request tools, tool_choice, model settings, PROJECT_SNAPSHOT, SELECTION_SNAPSHOT, LIBRARY_SNAPSHOT, and PENDING_MIX_PROPOSAL are authoritative if they conflict with older conversation memory.',
      '- Use the seeded contract for behavior, tone, follow-up handling, user-intent priority, action selection, and clean-row placement policy.',
      if (contextInstructions.trim().isNotEmpty) '',
      if (contextInstructions.trim().isNotEmpty) contextInstructions.trim(),
    ].join('\n').trim();
  }

  String _buildRequestLocalAiHints({required String userText}) {
    final text = userText.trim().toLowerCase();
    if (text.isEmpty) return '';
    final lines = <String>[];
    const enableStarterHints = true;
    const enableActionHints = true;
    const enableDropAndSectionHints = true;
    const enableCompoundTargetHints = true;
    final negatesStem = _negatesStemSeparation(text);

    if (negatesStem &&
        RegExp(r'\b(only|just)\b').hasMatch(text) &&
        RegExp(
          r'\b(bright|brighter|brighten|clear|clearer|presence|air)\b',
        ).hasMatch(text) &&
        RegExp(r'\b(vocal|vocals|voice)\b').hasMatch(text)) {
      lines
        ..add(
          '- Latest user negates further stem splitting but includes a positive vocal mix edit. Execute the positive edit; do not answer with only acknowledgement.',
        )
        ..add(
          '- For this turn, do not emit stem_separate. Prefer mix_model_request targeting the current vocal stem for brightness/clarity.',
        );
    }

    if (enableCompoundTargetHints) {
      final compoundStemPitchRequest =
          RegExp(
            r'\b(remove|split|separate|isolate|take out)\b[^.?!]{0,80}\b(vocal|vocals|voice)\b',
          ).hasMatch(text) &&
          RegExp(
            r'\b(lower|raise|change|shift|transpose|pitch|key|semitone|semitones)\b',
          ).hasMatch(text) &&
          RegExp(
            r'\b(background|backing|instrumental|music|song|track)\b',
          ).hasMatch(text) &&
          !negatesStem;
      if (compoundStemPitchRequest) {
        lines
          ..add(
            '- Compound stem+pitch request: emit one daw_assistant_actions tool call containing both stem_separate vocal_instrumental and clip_edit pitch_shift.',
          )
          ..add(
            '- For the pitch_shift action, target the resulting or existing instrumental/background/backing stem; use label_contains="Instrumental" when helpful. Treat one key as one semitone and preserve tempo.',
          );
      }
      if (RegExp(
        r'\b(original song|instrumental|backing|background|lead vocal|vocal stem|synth|piano|bass|drums|kick|snare|hat)\b',
      ).hasMatch(text)) {
        lines.add(
          '- Named-source priority: target the row/clip whose name, label, file, role, or instrument matches the user\'s named source even if another row is selected.',
        );
      }
    }

    final asksNewDrums =
        RegExp(
          r'\b(add|insert|put|place|make|create|generate|write)\b',
        ).hasMatch(text) &&
        RegExp(r'\b(drum|drums|kick|snare|hat|hats|loop)\b').hasMatch(text) &&
        !RegExp(r"\b(do\s+not|don't|dont)\s+add\b").hasMatch(text);
    if (asksNewDrums) {
      lines.add(
        '- Latest user asks to add drum/sample material. If LIBRARY_SNAPSHOT contains matching role aliases or paths, use sample_insert rather than an unsupported explanation.',
      );
    }

    final asksLofiStarter =
        enableStarterHints &&
        RegExp(r'\b(lofi|lo-fi)\b').hasMatch(text) &&
        RegExp(
          r'\b(make|create|generate|write|compose|build)\b',
        ).hasMatch(text) &&
        RegExp(
          r'\b(song|beat|track|instrumental|starter|idea|loop)\b',
        ).hasMatch(text) &&
        !text.contains('remix');
    if (asksLofiStarter) {
      lines
        ..add(
          '- Latest user asks for a new lofi starter song. Prefer one daw_assistant_actions call with a bounded 3-5 action starter arrangement rather than a vague reply.',
        )
        ..add(
          '- Include concrete musical material when assets exist: drums/loop from LIBRARY_SNAPSHOT, soft keys/chords, and bassline/sub. Use midi_compose only with concrete notes or progression.',
        )
        ..add(
          '- Put new musical parts on clean/new rows unless the user explicitly names the current/selected/named/numbered row. Do not use row_create alone as the result.',
        );
    } else if (RegExp(r'\b(lofi|lo-fi|remix)\b').hasMatch(text)) {
      lines.add(
        '- Latest user asks for a remix/style transformation. Use a bounded multi-step plan: concrete DAW edits first when requested/available, then a mix pass. Do enough to satisfy named parts without adding unrelated extras.',
      );
      final hasConcreteDawEdit = RegExp(
        r'\b(add|insert|put|place|pitch|lower|raise|shift|transpose|stem|split|separate|mute|solo|rename|delete|automation|duck|sidechain)\b',
      ).hasMatch(text);
      final hasSonicMixGoal = RegExp(
        r'\b(warm|warmer|warmth|space|spacious|reverb|delay|wide|wider|width|tone|polish|balance|saturat|compress|glue|bright|brighter|dark|darker)\b',
      ).hasMatch(text);
      if (hasConcreteDawEdit && hasSonicMixGoal) {
        lines.add(
          '- This remix request combines concrete DAW edits with sonic mix goals. If both tool families are available, the response is incomplete unless it emits both calls in this same turn: daw_assistant_actions for the concrete edits, then mix_model_request for the sonic pass. Do not only describe the mix pass in assistant_message.',
        );
      }
    }

    const levelTargetPattern =
        r'(?:vocal|voice|track|row|stem|pad|pads|bass|808|sub|drum|drums|kick|snare|hat|hats|guitar|piano|keys|synth|lead|instrumental)';
    final pitchDirectionRequest = RegExp(
      r'\b(pitch|transpose|octave|semitone|semitones|key)\b',
    ).hasMatch(text);
    final concreteLevelChangeRequest =
        !pitchDirectionRequest &&
        (RegExp(
              r'\b(volume|gain|level|fader|db|louder|quieter|turn up|turn down)\b',
            ).hasMatch(text) ||
            RegExp(
              r'\b(turn|bring|pull|push|take|make)\b[^.?!]{0,64}\b' +
                  levelTargetPattern +
                  r'\b[^.?!]{0,32}\b(up|down|lower|louder|quieter)\b',
            ).hasMatch(text) ||
            RegExp(
              r'\b' +
                  levelTargetPattern +
                  r'\b[^.?!]{0,64}\b(up|down|lower|louder|quieter|reduc|tuck)\b',
            ).hasMatch(text));

    if (enableActionHints) {
      if (RegExp(
        r'\b(remove|delete|take out|bypass|unbypass|toggle)\b[^.?!]{0,64}\b(effect|plugin|fx|distortion|compressor|compress|eq|reverb|delay|limiter|pitch corrector)\b',
      ).hasMatch(text)) {
        lines.add(
          '- Latest user asks for explicit plugin/effect CRUD. Use daw_assistant_actions effect_edit for the named plugin/effect; do not convert this into mix_model_request.',
        );
      }
      if (RegExp(
        r'\b(duck|ducking|sidechain|pump|pumping|fade|sweep)\b',
      ).hasMatch(text)) {
        lines.add(
          '- Latest user asks for time-varying movement/ducking. Use daw_assistant_actions automation_edit on the named row/track; do not answer that automation is unavailable when automation_edit is exposed.',
        );
      }
      if (RegExp(r'\b(pan|left|right|center)\b').hasMatch(text) &&
          RegExp(
            r'\b(row|track|pad|pads|vocal|bass|drum|instrumental|stem)\b',
          ).hasMatch(text)) {
        lines.add(
          '- Latest user asks for a concrete pan move. Use daw_assistant_actions row_mix set_pan/adjust_pan on the target row; do not use generic mix pan or refuse.',
        );
      }
    }

    if (enableDropAndSectionHints) {
      final asksDropContent =
          !concreteLevelChangeRequest &&
          (RegExp(
                r'\b(808|bass\s+drop|sub\s+drop|bass|sub)\b',
              ).hasMatch(text) ||
              (RegExp(r'\bdrop\b').hasMatch(text) &&
                  RegExp(
                    r'\b(add|insert|put|place|make|create|write|compose|hit|impact|fill|before|right before|hook)\b',
                  ).hasMatch(text)));
      if (concreteLevelChangeRequest &&
          RegExp(
            r'\b(down|lower|reduc|quieter|tuck|drop|too loud|swallowing)\b',
          ).hasMatch(text)) {
        lines.add(
          '- Volume drop routing: treat turn/bring/pull/take/make + named-row + down/lower/quieter language as row_mix for static level changes, or automation_edit when the prompt names a time range such as hook, chorus, verse, during, or whenever. Do not interpret 808/bass/sub wording as musical drop content when the user is changing level.',
        );
      }
      if (asksDropContent) {
        lines.add(
          '- Drop source selection: use an 808/sub/bass sample only when the user asks for 808, sub, bass, or bass drop. For generic drop/fill/hit/impact wording, prefer the best matching FX or drum source; compose MIDI bass only when the request is musically bass/sub oriented.',
        );
      }
      if (RegExp(
        r'\b(not an 808|not 808|no 808|without 808)\b',
      ).hasMatch(text)) {
        lines.add(
          '- Negative source constraint: the user rejected 808. Do not use an 808 sample path; for a bass/sub drop, compose MIDI with a visible bass/sub instrument or choose a non-808 bass source.',
        );
      }
      if (RegExp(
        r'\b(hook|chorus|verse|bridge|intro|outro|second verse|last chorus|first hook|later hook)\b',
      ).hasMatch(text)) {
        lines.add(
          '- Section placement: hook/chorus/verse/bridge labels are valid placement hints. If exact measures are unavailable, put the section label in placement/destination and proceed instead of asking for bar numbers.',
        );
      }
    }

    if (lines.isEmpty) return '';
    return <String>['REQUEST_LOCAL_AI_HINTS', ...lines].join('\n');
  }

  Map<String, dynamic> _buildOpenAiRequestBody({
    required List<Map<String, dynamic>> inputMessages,
    required String userText,
    String? aiFeature,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
    String? conversationId,
    String conversationContextInstructions = '',
    bool seededConversation = false,
    String seededConversationInstructionHash = '',
  }) {
    final normalizedAiFeature = _normalizeAiFeatureForProxy(aiFeature);
    final clientCapabilities = _readClientCapabilities(clientContext);
    final clientPolicy = _readClientPolicy(clientContext);
    final instructionOverlay = aiExecutionGuidance();
    var capabilitySignature = _clientCapabilitySignature(clientCapabilities);
    final contextRouteSignature = _contextRouteSignature(clientContext);
    if (contextRouteSignature.isNotEmpty) {
      capabilitySignature = [
        capabilitySignature,
        contextRouteSignature,
      ].join('|');
    }
    if (clientPolicy.isNotEmpty) {
      capabilitySignature = [
        capabilitySignature,
        _clientPolicySignature(clientPolicy),
      ].join('|');
    }
    if (instructionOverlay.isNotEmpty) {
      final overlayHash = crypto.sha256
          .convert(utf8.encode(instructionOverlay))
          .toString()
          .substring(0, 12);
      capabilitySignature = [
        capabilitySignature,
        'instruction_overlay:$overlayHash',
      ].join('|');
    }
    final toolSchemas = _directOpenAiToolSchemas();
    _filterDirectToolSchemas(toolSchemas, clientCapabilities);
    _filterDirectToolSchemasForIntent(
      toolSchemas,
      userText: userText,
      toolRoutingMode: _effectiveToolRoutingMode(clientContext),
    );
    final seedInstructions = _buildDirectSeedInstructions(
      clientCapabilities: clientCapabilities,
      clientPolicy: clientPolicy,
      instructionOverlay: instructionOverlay,
    );
    final requestLocalHints = _buildRequestLocalAiHints(userText: userText);
    final contextInstructions = conversationContextInstructions.trim();
    final seedHash = seededConversationInstructionHash.trim().isNotEmpty
        ? seededConversationInstructionHash.trim()
        : _conversationSeedHash(seedInstructions);
    final instructions = seededConversation
        ? _buildSeededConversationRequestInstructions(
            seedHash: seedHash,
            contextInstructions: <String>[
              if (requestLocalHints.isNotEmpty) requestLocalHints,
              if (contextInstructions.isNotEmpty) contextInstructions,
            ].join('\n\n').trim(),
          )
        : <String>[
            seedInstructions,
            if (requestLocalHints.isNotEmpty) requestLocalHints,
            if (contextInstructions.isNotEmpty) contextInstructions,
          ].join('\n\n').trim();
    final body = <String, dynamic>{
      'model': model,
      'instructions': instructions,
      'prompt_cache_key': _promptCacheKeyForFeature(
        normalizedAiFeature,
        capabilitySignature: capabilitySignature,
      ),
      'prompt_cache_retention': _promptCacheRetention,
      'input': inputMessages,
      'tools': toolSchemas,
      'tool_choice': 'required',
      'parallel_tool_calls': true,
      'max_output_tokens': _directOpenAiMaxOutputTokens,
    };
    final normalizedConversationId = (conversationId ?? '').trim();
    if (normalizedConversationId.isNotEmpty) {
      body['conversation'] = normalizedConversationId;
    }
    if (_supportsTemperature) {
      body['temperature'] = 0.2;
    }
    final reasoning = _defaultReasoning;
    if (reasoning != null) {
      body['reasoning'] = reasoning;
    }
    return body;
  }

  String _directConversationKey({
    required String sessionId,
    String? aiFeature,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
  }) {
    final normalizedFeature = _normalizeAiFeatureForProxy(aiFeature);
    final clientCapabilities = _readClientCapabilities(clientContext);
    final clientPolicy = _readClientPolicy(clientContext);
    final instructionOverlay = aiExecutionGuidance();
    var capabilitySignature = _clientCapabilitySignature(clientCapabilities);
    final contextRouteSignature = _contextRouteSignature(clientContext);
    if (contextRouteSignature.isNotEmpty) {
      capabilitySignature = <String>[
        capabilitySignature,
        contextRouteSignature,
      ].join('|');
    }
    if (clientPolicy.isNotEmpty) {
      capabilitySignature = <String>[
        capabilitySignature,
        _clientPolicySignature(clientPolicy),
      ].join('|');
    }
    if (instructionOverlay.isNotEmpty) {
      final overlayHash = crypto.sha256
          .convert(utf8.encode(instructionOverlay))
          .toString()
          .substring(0, 12);
      capabilitySignature = <String>[
        capabilitySignature,
        'instruction_overlay:$overlayHash',
      ].join('|');
    }
    final promptHash = crypto.sha256
        .convert(
          utf8.encode(
            _buildDirectSystemPrompt(clientCapabilities, clientPolicy),
          ),
        )
        .toString()
        .substring(0, 12);
    final signatureHash = crypto.sha256
        .convert(
          utf8.encode(
            '$model|$normalizedFeature|$_normalizedConversationStateMode|$capabilitySignature|$promptHash',
          ),
        )
        .toString()
        .substring(0, 12);
    return '${sessionId.trim()}|$normalizedFeature|$signatureHash';
  }

  Future<String> _ensureDirectOpenAiConversation(
    String conversationKey, {
    List<Map<String, dynamic>> seedItems = const <Map<String, dynamic>>[],
    String seedHash = '',
  }) async {
    final cached = _directConversationIds[conversationKey]?.trim() ?? '';
    if (cached.isNotEmpty) {
      _conversationTurnCounts[conversationKey] =
          (_conversationTurnCounts[conversationKey] ?? 0) + 1;
      return cached;
    }

    final response = await _postJson(
      uri: Uri.parse(_conversationsApiUrl),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: <String, dynamic>{
        'metadata': <String, dynamic>{
          'source': 'mixroom_direct_debug',
          'conversation_state_mode': _normalizedConversationStateMode,
          'conversation_key_hash': crypto.sha256
              .convert(utf8.encode(conversationKey))
              .toString()
              .substring(0, 16),
          if (seedHash.trim().isNotEmpty) 'seed_hash': seedHash.trim(),
        },
        if (seedItems.isNotEmpty) 'items': seedItems.take(20).toList(),
      },
    );
    final payload = _decodeJsonObject(response.body);
    final conversationId = payload?['id']?.toString().trim() ?? '';
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        conversationId.isEmpty) {
      throw StateError(
        'Could not create OpenAI conversation: ${response.statusCode}',
      );
    }
    _directConversationIds[conversationKey] = conversationId;
    _conversationTurnCounts[conversationKey] = 1;
    return conversationId;
  }

  String _buildConversationContextInstructions({
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    MixingResult? pendingMix,
  }) {
    final lines = <String>[
      'CURRENT PROJECT CONTEXT',
      'Treat this context as current request-local DAW state, not durable chat history.',
      'PROJECT_SNAPSHOT:',
      projectSnapshot,
    ];
    if (selectionSnapshot.trim().isNotEmpty) {
      lines
        ..add('')
        ..add('SELECTION_SNAPSHOT:')
        ..add(selectionSnapshot);
    }
    if (librarySnapshot.trim().isNotEmpty) {
      lines
        ..add('')
        ..add('LIBRARY_SNAPSHOT:')
        ..add(librarySnapshot);
    }
    if (pendingMix != null) {
      lines
        ..add('')
        ..add('PENDING_MIX_PROPOSAL:')
        ..add(jsonEncode(pendingMix.toJson()))
        ..add('')
        ..add(
          'A mix proposal was previously discussed in the chat at some point.',
        )
        ..add('You may refer to this if it is relevant to the current turn.')
        ..add('If it is not relevant, ignore it.');
    }
    return lines.join('\n').trim();
  }

  Map<String, dynamic> _buildProxyRequestBody({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    String? conversationSessionId,
    MixingResult? pendingMix,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
  }) {
    final normalizedAiFeature = _normalizeAiFeatureForProxy(aiFeature);
    final packedContext = _packContextSnapshots(
      mode: _readContextPackingMode(clientContext),
      projectSnapshot: projectSnapshot,
      selectionSnapshot: selectionSnapshot,
      librarySnapshot: librarySnapshot,
    );
    final requestContext = AnalyticsService.instance.buildRequestContext();
    final analyticsClientContext =
        (requestContext['client_context'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    requestContext['client_context'] = <String, dynamic>{
      ...analyticsClientContext,
      ...clientContext,
    };
    return {
      'conversation': conversation
          .map((m) => {'role': m['role'], 'content': m['content']})
          .toList(),
      'user_text': userText,
      'project_snapshot': packedContext.projectSnapshot,
      if (packedContext.selectionSnapshot.trim().isNotEmpty)
        'selection_snapshot': packedContext.selectionSnapshot,
      if (packedContext.librarySnapshot.trim().isNotEmpty)
        'library_snapshot': packedContext.librarySnapshot,
      if ((promptTraceId ?? '').trim().isNotEmpty)
        'prompt_trace_id': promptTraceId!.trim(),
      if ((projectId ?? '').trim().isNotEmpty) 'project_id': projectId,
      if (normalizedAiFeature.isNotEmpty) 'ai_feature': normalizedAiFeature,
      if (_usesOpenAiConversationState)
        'conversation_state_mode': _normalizedConversationStateMode,
      if (_usesOpenAiConversationState &&
          (conversationSessionId ?? '').trim().isNotEmpty)
        'conversation_session_id': conversationSessionId!.trim(),
      if (pendingMix != null) 'pending_mix': pendingMix.toJson(),
      ...requestContext,
    };
  }

  String _normalizeAiFeatureForProxy(String? aiFeature) {
    final value = (aiFeature ?? '').trim();
    if (value.isEmpty) return 'ai_chat';

    switch (value) {
      case 'assistant_chat':
      case 'one_button_mix':
      case 'ai_chat':
        return 'ai_chat';
      default:
        return value;
    }
  }

  Uri _resolveProxyUri({String? pathOverride}) {
    final base = proxyApiBaseUrl.trim();
    final path = (pathOverride ?? proxyPath).trim().isEmpty
        ? '/v1/llm/responses'
        : (pathOverride ?? proxyPath);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  Future<String?> _resolveProxyAuthToken({bool forceRefresh = false}) async {
    final primaryProvider = forceRefresh
        ? refreshAuthTokenProvider
        : authTokenProvider;
    final primaryToken = await primaryProvider?.call();
    final safePrimaryToken = primaryToken?.trim() ?? '';
    if (safePrimaryToken.isNotEmpty) return safePrimaryToken;

    if (!forceRefresh && refreshAuthTokenProvider != null) {
      final refreshedToken = await refreshAuthTokenProvider!.call();
      final safeRefreshedToken = refreshedToken?.trim() ?? '';
      if (safeRefreshedToken.isNotEmpty) return safeRefreshedToken;
    }
    return null;
  }

  Future<http.Response> _postProxyJson({
    required String token,
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    required String selectionSnapshot,
    required String librarySnapshot,
    required String? promptTraceId,
    required String? projectId,
    required String? aiFeature,
    required String? conversationSessionId,
    required MixingResult? pendingMix,
    required Map<String, dynamic> clientContext,
  }) {
    return _postJson(
      uri: _resolveProxyUri(),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: _buildProxyRequestBody(
        conversation: conversation,
        userText: userText,
        projectSnapshot: projectSnapshot,
        selectionSnapshot: selectionSnapshot,
        librarySnapshot: librarySnapshot,
        promptTraceId: promptTraceId,
        projectId: projectId,
        aiFeature: aiFeature,
        conversationSessionId: conversationSessionId,
        pendingMix: pendingMix,
        clientContext: clientContext,
      ),
    );
  }

  String _limitsProxyPath() {
    final path = proxyPath.trim().isEmpty ? '/v1/llm/responses' : proxyPath;
    if (path.endsWith('/responses')) {
      return '${path.substring(0, path.length - '/responses'.length)}/limits';
    }
    return '${path.replaceFirst(RegExp(r'/$'), '')}/limits';
  }

  Future<http.Response> _postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
    Duration? timeoutOverride,
  }) {
    return _httpClient
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeoutOverride ?? requestTimeout);
  }

  void _debugDumpJson(
    String scope,
    String label,
    Object? value, {
    int maxChars = 12000,
  }) {
    if (!kAiDebugLogs || !kAiDebugVerbose) return;
    String encoded;
    try {
      encoded = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      encoded = value.toString();
    }
    if (encoded.length > maxChars) {
      encoded = '${encoded.substring(0, maxChars)}\n... <truncated>';
    }
    aiDebugBlock(scope, label, encoded);
  }

  void _debugDumpRawBody(
    String scope,
    String label,
    String body, {
    int maxChars = 12000,
  }) {
    if (!kAiDebugLogs || !kAiDebugVerbose) return;
    final trimmed = body.length > maxChars
        ? '${body.substring(0, maxChars)}\n... <truncated>'
        : body;
    aiDebugBlock(scope, label, trimmed);
  }

  Future<http.Response> _getJson({
    required Uri uri,
    required Map<String, String> headers,
  }) {
    return _httpClient.get(uri, headers: headers).timeout(requestTimeout);
  }

  Map<String, dynamic>? _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  AiPromptRateLimitStatus? _parsePromptRateLimitStatus(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return AiPromptRateLimitStatus.fromJson(raw);
    }
    if (raw is Map) {
      return AiPromptRateLimitStatus.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  Map<String, dynamic> _buildResponseMeta(Map<String, dynamic>? payload) {
    if (payload == null) return const <String, dynamic>{};
    final status = _parsePromptRateLimitStatus(payload['prompt_rate_limit']);
    final meta = <String, dynamic>{};
    if (status != null) {
      meta['prompt_rate_limit'] = status.toJson();
    }
    final softError = payload['soft_error'];
    if (softError is Map<String, dynamic>) {
      meta['soft_error'] = softError;
    } else if (softError is Map) {
      meta['soft_error'] = softError.cast<String, dynamic>();
    }
    final usage = payload['usage'];
    if (usage is Map<String, dynamic>) {
      meta['usage'] = usage;
      final cachedPromptTokens = _cachedPromptTokensFromUsage(usage);
      if (cachedPromptTokens > 0) {
        meta['cached_prompt_tokens'] = cachedPromptTokens;
      }
    } else if (usage is Map) {
      final normalizedUsage = usage.cast<String, dynamic>();
      meta['usage'] = normalizedUsage;
      final cachedPromptTokens = _cachedPromptTokensFromUsage(normalizedUsage);
      if (cachedPromptTokens > 0) {
        meta['cached_prompt_tokens'] = cachedPromptTokens;
      }
    }
    final observability = payload['observability'];
    if (observability is Map<String, dynamic>) {
      meta['observability'] = observability;
    } else if (observability is Map) {
      meta['observability'] = observability.cast<String, dynamic>();
    }
    final responseId = payload['id']?.toString().trim() ?? '';
    final responseModel = payload['model']?.toString().trim() ?? '';
    if (responseId.isNotEmpty || responseModel.isNotEmpty) {
      meta['observability'] = <String, dynamic>{
        if (meta['observability'] is Map<String, dynamic>)
          ...(meta['observability'] as Map<String, dynamic>),
        if (meta['observability'] is Map)
          ...(meta['observability'] as Map).cast<String, dynamic>(),
        if (responseId.isNotEmpty) 'provider_response_id': responseId,
        if (responseModel.isNotEmpty) 'effective_model': responseModel,
      };
    }
    return meta;
  }

  Map<String, dynamic> _mergeMetaObservability(
    Map<String, dynamic>? meta,
    Map<String, dynamic> localObservability,
  ) {
    final merged = <String, dynamic>{if (meta != null) ...meta};
    final existingObservability = merged['observability'];
    final observability = <String, dynamic>{
      if (existingObservability is Map<String, dynamic>)
        ...existingObservability,
      if (existingObservability is Map)
        ...existingObservability.cast<String, dynamic>(),
      ...localObservability,
    };
    merged['observability'] = observability;
    return merged;
  }

  int _cachedPromptTokensFromUsage(Map<String, dynamic> usage) {
    for (final key in const ['input_tokens_details', 'prompt_tokens_details']) {
      final details = usage[key];
      if (details is Map<String, dynamic>) {
        return (details['cached_tokens'] as num?)?.toInt() ?? 0;
      }
      if (details is Map) {
        return (details['cached_tokens'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  String _formatResetCountdown(DateTime? resetsAt) {
    if (resetsAt == null) return '';
    final remaining = resetsAt.toLocal().difference(DateTime.now());
    if (remaining.inSeconds <= 0) return 'a moment';
    if (remaining.inDays >= 1) {
      final hours = remaining.inHours.remainder(24);
      return hours > 0
          ? '${remaining.inDays}d ${hours}h'
          : '${remaining.inDays}d';
    }
    if (remaining.inHours >= 1) {
      final minutes = remaining.inMinutes.remainder(60);
      return minutes > 0
          ? '${remaining.inHours}h ${minutes}m'
          : '${remaining.inHours}h';
    }
    if (remaining.inMinutes >= 1) {
      return '${remaining.inMinutes}m';
    }
    return '${remaining.inSeconds}s';
  }

  String _rateLimitMessage(AiPromptRateLimitStatus? status, String fallback) {
    if (status == null) return fallback;
    final limitLabel = status.blockedBy == 'weekly_prompts'
        ? 'weekly'
        : 'daily';
    final wait = _formatResetCountdown(status.blockedResetAt);
    if (wait.isEmpty) {
      return 'You have reached the $limitLabel prompt limit. Please try again later.';
    }
    return 'You have reached the $limitLabel prompt limit. Try again in $wait.';
  }

  bool _isPromptRateLimitResponse(
    int statusCode,
    Map<String, dynamic>? payload,
    AiPromptRateLimitStatus? status,
  ) {
    if (statusCode != 429) return false;
    if (status?.isBlocked == true) return true;
    return payload?['error'] == 'prompt_rate_limit_hit';
  }

  LlmResult _recoverableTextResult(
    String message, {
    String? softErrorCode,
    Map<String, dynamic>? meta,
  }) {
    final mergedMeta = <String, dynamic>{
      if (meta != null) ...meta,
      if ((softErrorCode ?? '').trim().isNotEmpty)
        'soft_error': <String, dynamic>{
          'code': softErrorCode!.trim(),
          'usage_refunded': true,
        },
    };
    return LlmResult.text(message, {
      'message': message,
      'cancels_pending': false,
    }, meta: mergedMeta);
  }

  Future<AiPromptRateLimitStatus?> fetchPromptRateLimitStatus() async {
    if (!_isProxyEnabled) return null;
    final token = await authTokenProvider?.call();
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    try {
      final response = await _getJson(
        uri: _resolveProxyUri(pathOverride: _limitsProxyPath()),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode != 200) return null;
      final payload = _decodeJsonObject(response.body);
      return _parsePromptRateLimitStatus(payload?['prompt_rate_limit']);
    } catch (_) {
      return null;
    }
  }

  String _fallbackAssistantText(String toolName) {
    switch (toolName) {
      case 'mix_model_request':
        return '';
      case 'daw_assistant_actions':
        return '';
      default:
        return "I couldn't complete that request just now. Please try again.";
    }
  }

  String _invalidToolCallFallbackText(
    String toolName,
    dynamic rawArgs, {
    required String userText,
  }) {
    final decoded = _decodeToolArgs(rawArgs);
    final candidate = decoded == null
        ? ''
        : _sanitizeUserFacingText(
            decoded['assistant_message'] ?? decoded['message'],
            toolName: toolName,
            userText: userText,
            allowFallback: false,
          );
    if (candidate.isNotEmpty) {
      return '$candidate\n\nI understood the intent, but the action payload was incomplete or invalid, so nothing changed.';
    }
    return "I understood the intent, but the action payload was incomplete or invalid, so nothing changed.";
  }

  String _sanitizeUserFacingText(
    Object? value, {
    required String toolName,
    required String userText,
    bool allowFallback = true,
  }) {
    final raw = (value?.toString() ?? '').trim();
    final fallback = _fallbackAssistantText(toolName);
    if (raw.isEmpty) return allowFallback ? fallback : '';

    final lowered = raw.toLowerCase();
    if (_toolTextLeakMarkers.any(lowered.contains) ||
        RegExp(r'\bisempty\s*=\s*(true|false)\b').hasMatch(lowered) ||
        raw.startsWith('{') ||
        raw.startsWith('[')) {
      return allowFallback ? fallback : '';
    }

    return raw;
  }

  static const Set<String> _toolTextLeakMarkers = <String>{
    'mix_model_request',
    'daw_assistant_actions',
    'informational_response',
    '"assistant_message"',
    '"row_index"',
    '"target_id"',
    'project snapshot',
    'selection snapshot',
    'project_snapshot',
    'selection_snapshot',
    'pending_mix_proposal',
    'isempty = true',
    'isempty = false',
    'isempty=true',
    'isempty=false',
    'clip_index',
    'clip_indices',
    'row_index:',
  };

  static const Set<String> _dawAssistantActionTypes = <String>{
    'tutorial',
    'clarify',
    'project_edit',
    'sample_insert',
    'clip_edit',
    'effect_edit',
    'row_group_edit',
    'row_color_edit',
    'automation_edit',
    'midi_compose',
    'stem_separate',
    'role_override',
    'audio_enhance',
  };

  static const Set<String> _allowedClipEditOperations = <String>{
    'trim',
    'auto_trim',
    'cut',
    'stretch',
    'pitch_shift',
    'glue',
    'move',
    'tempo_follow',
    'auto_bpm_align',
    'align_first_sound',
    'tempo_detect_set_project',
    'duplicate',
    'delete',
    'dialog_cleanup',
    'dialog_remove_range',
    'dialog_tighten_pauses',
    'dialog_lift_quiet',
  };

  static const Set<String> _allowedEffectEditOperations = <String>{
    'add',
    'remove',
    'bypass',
    'unbypass',
    'toggle_bypass',
  };

  static const Set<String> _allowedAutomationEditOperations = <String>{
    'set_points',
    'add_ramp',
    'clear',
    'apply_template',
  };

  static const Set<String> _allowedMidiComposeOperations = <String>{
    'create_clip',
    'compose_bassline',
    'compose_pattern',
    'replace_notes',
    'append_notes',
    'chop_notes',
    'transpose_notes',
    'convert_audio_to_midi',
  };

  static const Set<String> _allowedStemSeparateOperations = <String>{
    'vocal_instrumental',
  };

  static const Set<String> _allowedProjectEditOperations = <String>{
    'set_tempo',
  };

  static const Set<String> _allowedSampleInsertOperations = <String>{
    'insert_audio_clips',
    'replace_audio_clips',
  };

  static const Set<String> _allowedRowGroupEditOperations = <String>{
    'create',
    'remove_row',
    'toggle_collapsed',
  };

  static const Set<String> _allowedRowColorEditOperations = <String>{
    'set',
    'clear',
  };

  static const Set<String> _allowedRoleOverrideOperations = <String>{
    'set',
    'clear',
  };

  String _normalizeActionToken(Object? raw) {
    return raw
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _normalizeClipEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'split': 'cut',
      'split_clip': 'cut',
      'cut_clip': 'cut',
      'resize': 'stretch',
      'resize_clip': 'stretch',
      'pitch': 'pitch_shift',
      'pitch_clip': 'pitch_shift',
      'pitch_shift_clip': 'pitch_shift',
      'shift_pitch': 'pitch_shift',
      'lower_pitch': 'pitch_shift',
      'raise_pitch': 'pitch_shift',
      'lower_key': 'pitch_shift',
      'raise_key': 'pitch_shift',
      'change_key': 'pitch_shift',
      'transpose_audio': 'pitch_shift',
      'transpose_clip': 'pitch_shift',
      'glue_clips': 'glue',
      'merge': 'glue',
      'merge_clip': 'glue',
      'merge_clips': 'glue',
      'consolidate': 'glue',
      'consolidate_clip': 'glue',
      'consolidate_clips': 'glue',
      'bounce_clip': 'glue',
      'bounce_clips': 'glue',
      'move_clip': 'move',
      'reposition': 'move',
      'shift': 'move',
      'nudge': 'move',
      'copy': 'duplicate',
      'copy_clip': 'duplicate',
      'remove': 'delete',
      'remove_clip': 'delete',
      'delete_clip': 'delete',
      'tempo_follow_project': 'tempo_follow',
      'align_tempo': 'auto_bpm_align',
      'align_to_project_tempo': 'auto_bpm_align',
      'align_onset': 'align_first_sound',
      'onset_align': 'align_first_sound',
      'first_sound_align': 'align_first_sound',
      'align_volume_start': 'align_first_sound',
      'align_audio_start': 'align_first_sound',
      'align_to_first_sound': 'align_first_sound',
      'detect_tempo_set_project': 'tempo_detect_set_project',
    };
    return aliases[token] ?? token;
  }

  String _normalizeEffectEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'delete': 'remove',
      'delete_effect': 'remove',
      'remove_effect': 'remove',
      'take_out': 'remove',
      'insert': 'add',
      'ensure': 'add',
      'ensure_effect': 'add',
      'add_effect': 'add',
      'insert_effect': 'add',
      'disable': 'bypass',
      'mute': 'bypass',
      'enable': 'unbypass',
      'unmute': 'unbypass',
      'toggle': 'toggle_bypass',
    };
    return aliases[token] ?? token;
  }

  String _normalizeAutomationEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'create': 'set_points',
      'create_clip': 'set_points',
      'new_clip': 'set_points',
      'add_clip': 'set_points',
      'insert_clip': 'set_points',
      'set_clip_points': 'set_points',
      'clear_clips': 'clear',
      'delete_clip': 'clear',
      'remove_clip': 'clear',
    };
    return aliases[token] ?? token;
  }

  String _normalizeProjectEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'set_bpm': 'set_tempo',
      'change_bpm': 'set_tempo',
      'set_project_bpm': 'set_tempo',
      'change_project_bpm': 'set_tempo',
      'set_project_tempo': 'set_tempo',
      'change_tempo': 'set_tempo',
    };
    return aliases[token] ?? token;
  }

  String _normalizeSampleInsertOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'insert_audio_clip': 'insert_audio_clips',
      'insert_sample': 'insert_audio_clips',
      'insert_samples': 'insert_audio_clips',
      'add_sample': 'insert_audio_clips',
      'add_samples': 'insert_audio_clips',
      'insert_library_audio': 'insert_audio_clips',
      'replace_audio_clip': 'replace_audio_clips',
      'replace_sample': 'replace_audio_clips',
      'replace_samples': 'replace_audio_clips',
      'swap_sample': 'replace_audio_clips',
      'swap_samples': 'replace_audio_clips',
      'swap_audio_clips': 'replace_audio_clips',
      'change_sample': 'replace_audio_clips',
    };
    return aliases[token] ?? token;
  }

  String _normalizeMidiComposeOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'compose': 'compose_pattern',
      'create': 'create_clip',
      'create_clip': 'create_clip',
      'new_clip': 'create_clip',
      'new_midi_clip': 'create_clip',
      'compose_notes': 'compose_pattern',
      'write_pattern': 'compose_pattern',
      'generate_pattern': 'compose_pattern',
      'make_pattern': 'compose_pattern',
      'compose_bass': 'compose_bassline',
      'write_bassline': 'compose_bassline',
      'generate_bassline': 'compose_bassline',
      'make_bassline': 'compose_bassline',
      'replace': 'replace_notes',
      'overwrite_notes': 'replace_notes',
      'set_notes': 'replace_notes',
      'append': 'append_notes',
      'add_notes': 'append_notes',
      'extend_notes': 'append_notes',
      'transpose': 'transpose_notes',
      'transpose_note': 'transpose_notes',
      'transpose_notes': 'transpose_notes',
      'shift_pitch': 'transpose_notes',
      'pitch_shift': 'transpose_notes',
      'octave_up': 'transpose_notes',
      'octave_down': 'transpose_notes',
      'audio_to_midi': 'convert_audio_to_midi',
      'convert_to_midi': 'convert_audio_to_midi',
      'transcribe_audio': 'convert_audio_to_midi',
      'extract_midi': 'convert_audio_to_midi',
      'chop': 'chop_notes',
      'chop_note': 'chop_notes',
      'note_chop': 'chop_notes',
      'note_chopper': 'chop_notes',
      'splice_notes': 'chop_notes',
      'slice_notes': 'chop_notes',
      'split_notes': 'chop_notes',
      'grid_chop': 'chop_notes',
      'ratchet': 'chop_notes',
      'stutter': 'chop_notes',
    };
    return aliases[token] ?? token;
  }

  String _normalizeRoleOverrideOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    if (token == 'remove' || token == 'unset' || token == 'delete') {
      return 'clear';
    }
    return token;
  }

  String _normalizeRowGroupEditOperation(Object? raw) {
    final token = _normalizeActionToken(raw);
    const aliases = <String, String>{
      'group': 'create',
      'group_rows': 'create',
      'create_group': 'create',
      'create_row_group': 'create',
      'make_group': 'create',
      'make_row_group': 'create',
      'ungroup_row': 'remove_row',
      'remove_from_group': 'remove_row',
      'remove_row_from_group': 'remove_row',
      'toggle': 'toggle_collapsed',
      'fold': 'toggle_collapsed',
      'unfold': 'toggle_collapsed',
      'collapse': 'toggle_collapsed',
      'expand': 'toggle_collapsed',
      'toggle_group': 'toggle_collapsed',
      'toggle_row_group': 'toggle_collapsed',
    };
    return aliases[token] ?? token;
  }

  bool _isKnownAutomationTemplate(String templateRaw) {
    final template = templateRaw.trim().toLowerCase();
    return template == 'sidechain' ||
        template == 'sidechain_pump' ||
        template == 'pump' ||
        template == 'sidechain_from_kick' ||
        template == 'kick_sidechain' ||
        template == 'duck_to_kick' ||
        template == 'kick_duck' ||
        template == 'reverb_tail' ||
        template == 'tail' ||
        template == 'decay' ||
        template == 'filter_sweep' ||
        template == 'sweep' ||
        template == 'lowpass_sweep' ||
        template == 'highpass_sweep' ||
        template == 'auto_pan' ||
        template == 'autopan' ||
        template == 'stereo_motion' ||
        template == 'stereo_direction' ||
        template == 'pan_motion' ||
        template == 'left_right_motion';
  }

  Map<String, dynamic> _actionTargetMap(Map<String, dynamic> data) {
    final rawTarget = data['target'];
    if (rawTarget is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawTarget);
    }
    if (rawTarget is Map) {
      return Map<String, dynamic>.from(rawTarget);
    }
    return <String, dynamic>{};
  }

  bool _hasExplicitDialogRangePayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final fromMs = _parseActionDouble(data['from_ms'] ?? target['from_ms']);
    final toMs = _parseActionDouble(data['to_ms'] ?? target['to_ms']);
    if (fromMs != null && toMs != null) return true;
    final rawRanges = data['ranges'] ?? target['ranges'];
    if (rawRanges is! List) return false;
    for (final raw in rawRanges) {
      if (raw is! Map) continue;
      final range = Map<String, dynamic>.from(raw);
      final rangeFrom = _parseActionDouble(range['from_ms']);
      final rangeTo = _parseActionDouble(range['to_ms']);
      if (rangeFrom != null && rangeTo != null) return true;
    }
    return false;
  }

  bool _hasExplicitDialogAnchorPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    return _parseActionDouble(data['at_ms'] ?? target['at_ms']) != null ||
        _parseActionDouble(data['time_ms'] ?? target['time_ms']) != null;
  }

  bool _hasCompleteDialogRemoveRangePayload(Map<String, dynamic> data) {
    return _hasExplicitDialogRangePayload(data) ||
        _hasExplicitDialogAnchorPayload(data);
  }

  bool _hasAnyExplicitActionValue(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final target = _actionTargetMap(data);
    for (final key in keys) {
      final value = data.containsKey(key) ? data[key] : target[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      if (value is List && value.isEmpty) continue;
      return true;
    }
    return false;
  }

  bool _hasMeaningfulMovePayload(Map<String, dynamic> data) {
    if (_hasAnyExplicitActionValue(data, const <String>[
      'new_start_ms',
      'start_ms',
      'paste_start_ms',
      'start_measure',
      'new_start_measure',
      'paste_start_measure',
      'start_bar',
      'new_start_bar',
      'paste_start_bar',
      'start_beat',
      'new_start_beat',
      'paste_start_beat',
    ])) {
      return true;
    }

    if (_hasAnyExplicitActionValue(data, const <String>[
      'direction',
      'move_to',
      'align_to',
    ])) {
      return true;
    }

    final numericKeys = <String>[
      'delta_ms',
      'move_ms',
      'shift_ms',
      'delta_beats',
      'move_beats',
      'shift_beats',
      'delta_measures',
      'move_measures',
      'shift_measures',
      'delta_bars',
      'move_bars',
      'shift_bars',
    ];
    for (final key in numericKeys) {
      final value = _parseActionDouble(
        data[key] ?? _actionTargetMap(data)[key],
      );
      if (value != null && value.abs() > 1e-9) return true;
    }

    final integerKeys = <String>[
      'row_index',
      'target_row_index',
      'dest_row_index',
      'new_row_index',
      'row',
      'target_row',
      'row_delta',
      'delta_rows',
      'step_rows',
    ];
    for (final key in integerKeys) {
      final value = _parseActionInt(data[key] ?? _actionTargetMap(data)[key]);
      if (value != null) {
        if (key.contains('delta') || key.contains('step')) {
          if (value != 0) return true;
        } else {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasSupportedCutPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final scope = (target['scope'] ?? data['scope'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (scope == 'all' ||
        scope == 'all_audio' ||
        scope == 'all_selected_audio') {
      return false;
    }
    if (_hasExplicitDialogRangePayload(data)) {
      return false;
    }
    final clipIndices =
        (data['clip_indices'] as List?) ?? (target['clip_indices'] as List?);
    if (clipIndices != null && clipIndices.length > 1) {
      return false;
    }
    return true;
  }

  bool _hasMidiLengthPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final lengthMeasures = _parseActionDouble(
      data['length_measures'] ?? target['length_measures'],
    );
    if (lengthMeasures != null &&
        lengthMeasures.isFinite &&
        lengthMeasures > 0.0) {
      return true;
    }
    final lengthBeats = _parseActionDouble(
      data['length_beats'] ?? target['length_beats'],
    );
    return lengthBeats != null && lengthBeats.isFinite && lengthBeats > 0.0;
  }

  bool _parseActionBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final token = raw.trim().toLowerCase();
      return token == 'true' || token == '1' || token == 'yes';
    }
    return false;
  }

  bool _hasPreserveExistingMidiPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final preserve = _parseActionBool(
      data['preserve_existing_notes'] ?? target['preserve_existing_notes'],
    );
    if (!preserve) return false;
    final operation = data['operation']?.toString().trim().toLowerCase() ?? '';
    if (operation != 'replace_notes' && operation != 'append_notes') {
      return false;
    }
    if (!_hasMidiLengthPayload(data) || _hasMidiPayload(data)) {
      return false;
    }
    if (AssistantActionUtils.hasStyleDrivenMidiGenerationDirectives(
      data,
      target: target,
    )) {
      return false;
    }
    return true;
  }

  bool _looksLikePackagedLibraryReference(String libraryPath) {
    final normalized = libraryPath.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.startsWith('role:')) return true;
    return normalized.contains('/') || normalized.contains('\\');
  }

  bool _looksLikeLoopLibraryReference(String libraryPath) {
    final normalized = libraryPath.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('/loops/') ||
        normalized.contains('\\loops\\') ||
        RegExp(r'(^|[/\\])loops?([/\\]|$)').hasMatch(normalized) ||
        RegExp(r'\bloop\b').hasMatch(normalized);
  }

  bool _hasMusicalSpanPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    for (final key in const <String>[
      'length_ms',
      'length_measures',
      'length_beats',
      'until_ms',
      'until_measure',
      'until_beat',
    ]) {
      final value = _parseActionDouble(data[key] ?? target[key]);
      if (value != null && value.isFinite && value > 0.0) {
        return true;
      }
    }
    return false;
  }

  bool _hasRepeatingPlacementPayload(Map<String, dynamic> data) {
    final target = _actionTargetMap(data);
    final repeatCount = _parseActionInt(
      data['repeat_count'] ??
          target['repeat_count'] ??
          data['copies'] ??
          target['copies'] ??
          data['count'] ??
          target['count'],
    );
    if (repeatCount != null && repeatCount > 1) {
      return true;
    }
    for (final key in const <String>[
      'step_ms',
      'step_measures',
      'step_beats',
      'spacing_ms',
      'spacing_measures',
      'spacing_beats',
    ]) {
      final value = _parseActionDouble(data[key] ?? target[key]);
      if (value != null && value.isFinite && value > 0.0) {
        return true;
      }
    }
    return false;
  }

  bool _isValidSampleInsertItem(
    Map<String, dynamic> item, {
    required String operation,
  }) {
    final rawTarget = item['target'];
    final target = rawTarget is Map<String, dynamic>
        ? rawTarget
        : (rawTarget is Map
              ? Map<String, dynamic>.from(rawTarget)
              : const <String, dynamic>{});
    final libraryPath =
        (item['library_path'] ?? target['library_path'])?.toString().trim() ??
        '';
    if (!_looksLikePackagedLibraryReference(libraryPath)) {
      return false;
    }
    if (operation == 'replace_audio_clips') {
      return target.isNotEmpty ||
          item.containsKey('clip_index') ||
          item.containsKey('clip_indices') ||
          item.containsKey('row_index');
    }
    if (_hasMusicalSpanPayload(item) &&
        !_looksLikeLoopLibraryReference(libraryPath) &&
        !_hasRepeatingPlacementPayload(item)) {
      return false;
    }
    return true;
  }

  String _normalizeTutorialTargetId(Object? raw) {
    final targetId = raw?.toString().trim() ?? '';
    final match = RegExp(
      r'^(row:\d+:)fx_index:([^:]+)(:param:.+)?$',
    ).firstMatch(targetId);
    if (match == null) return targetId;
    final effectRef = (match.group(2) ?? '').trim();
    if (RegExp(r'^\d+$').hasMatch(effectRef)) return targetId;
    final suffix = match.group(3) ?? '';
    return '${match.group(1)}fx_contains:$effectRef$suffix';
  }

  int? _parseActionInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  double? _parseActionDouble(dynamic raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  Map<String, dynamic> _normalizeMidiNotePayload(Map<String, dynamic> rawNote) {
    final note = Map<String, dynamic>.from(rawNote);
    final pitch = AssistantActionUtils.midiPitchFromRaw(
      note['pitch'] ?? note['midi'] ?? note['note'] ?? note['note_name'],
      fallbackOctave: 3,
    );
    if (pitch != null) {
      note['pitch'] = pitch.clamp(0, 127).toInt();
    }

    final startBeat = AssistantActionUtils.resolveMidiNoteStartBeat(note);
    if (startBeat != null) {
      note['start_beat'] = startBeat;
    }

    final lengthBeats = AssistantActionUtils.resolveMidiNoteLengthBeats(note);
    if (lengthBeats != null) {
      note['length_beats'] = lengthBeats;
    }

    final velocity = AssistantActionUtils.normalizeMidiVelocity(
      note['velocity'],
    );
    if (velocity != null) {
      note['velocity'] = velocity;
    }

    return note;
  }

  List<Map<String, dynamic>> _normalizeMidiNotesPayload(dynamic rawNotes) {
    if (rawNotes is! List) return const <Map<String, dynamic>>[];
    final normalized = <Map<String, dynamic>>[];
    for (final raw in rawNotes) {
      if (raw is! Map) continue;
      normalized.add(_normalizeMidiNotePayload(Map<String, dynamic>.from(raw)));
    }
    if (_looksLikeOneBasedBeatGrid(normalized)) {
      for (final note in normalized) {
        final startBeat = _parseActionDouble(note['start_beat']);
        if (startBeat == null) continue;
        note['start_beat'] = math.max(0.0, startBeat - 1.0);
      }
    }
    return normalized;
  }

  bool _looksLikeOneBasedBeatGrid(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) return false;
    double? minStartBeat;
    var sawExactOne = false;
    for (final note in notes) {
      final startBeat = _parseActionDouble(note['start_beat']);
      if (startBeat == null || !startBeat.isFinite || startBeat <= 0.0) {
        return false;
      }
      minStartBeat = minStartBeat == null
          ? startBeat
          : math.min(minStartBeat, startBeat);
      if ((startBeat - 1.0).abs() < 1e-6) {
        sawExactOne = true;
      }
    }
    return sawExactOne &&
        minStartBeat != null &&
        (minStartBeat - 1.0).abs() < 1e-6;
  }

  int? _parseRowAlias(dynamic raw, {required bool oneBased}) {
    final v = _parseActionInt(raw);
    if (v == null) return null;
    if (oneBased) {
      if (v == 0) return 0;
      return v > 0 ? v - 1 : null;
    }
    return v >= 0 ? v : null;
  }

  int? _extractNormalizedRowIndex(
    Map<String, dynamic> data,
    Map<String, dynamic> target,
  ) {
    int? pick(List<String> keys, {required bool oneBased}) {
      for (final key in keys) {
        final fromData = _parseRowAlias(data[key], oneBased: oneBased);
        if (fromData != null) return fromData;
        final fromTarget = _parseRowAlias(target[key], oneBased: oneBased);
        if (fromTarget != null) return fromTarget;
      }
      return null;
    }

    return pick(const [
          'row_index',
          'track_index',
          'target_row_index',
        ], oneBased: false) ??
        pick(const ['row', 'target_row'], oneBased: true) ??
        pick(const ['row_number', 'track_number', 'track'], oneBased: true);
  }

  Map<String, dynamic> _normalizeSampleInsertItem(
    Map<String, dynamic> rawItem,
  ) {
    final item = Map<String, dynamic>.from(rawItem);
    final rawTarget = item['target'];
    final target = rawTarget is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawTarget)
        : (rawTarget is Map
              ? Map<String, dynamic>.from(rawTarget)
              : <String, dynamic>{});
    final rowIndex = _extractNormalizedRowIndex(item, target);
    if (rowIndex != null) {
      item['row_index'] = rowIndex;
      target['row_index'] = rowIndex;
    }
    item['target'] = target;
    return item;
  }

  List<Map<String, dynamic>> _postProcessNormalizedActions(
    List<Map<String, dynamic>> actions,
  ) {
    final normalized = actions
        .map(
          (action) => <String, dynamic>{
            'type': action['type'],
            'data': Map<String, dynamic>.from(
              action['data'] as Map<String, dynamic>,
            ),
          },
        )
        .toList(growable: false);
    final tempoBpm = _normalizedProjectTempoBpm(normalized);
    for (final action in normalized) {
      final type = action['type']?.toString().trim().toLowerCase() ?? '';
      if (type != 'sample_insert') continue;
      _spreadDrumSampleInsertRows(action['data'] as Map<String, dynamic>);
      _repairBackbeatSampleInsert(
        action['data'] as Map<String, dynamic>,
        tempoBpm: tempoBpm,
      );
    }
    return normalized;
  }

  String? _drumSampleRowBucket(String? role) {
    switch (role) {
      case 'kick':
        return 'kick';
      case 'snare':
      case 'clap':
        return 'snare_clap';
      case 'hat':
        return 'hat';
      case 'perc':
        return 'perc';
      case 'cymbal':
        return 'cymbal';
      case 'tom':
        return 'tom';
      default:
        return null;
    }
  }

  void _setSampleInsertItemRow(Map<String, dynamic> item, int rowIndex) {
    final rawTarget = item['target'];
    final target = rawTarget is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawTarget)
        : (rawTarget is Map
              ? Map<String, dynamic>.from(rawTarget)
              : <String, dynamic>{});
    item['row_index'] = rowIndex;
    target['row_index'] = rowIndex;
    item['target'] = target;
  }

  void _spreadDrumSampleInsertRows(Map<String, dynamic> data) {
    final operation = data['operation']?.toString().trim().toLowerCase() ?? '';
    if (operation != 'insert_audio_clips' && operation != 'insert_audio_clip') {
      return;
    }
    final rawItems = data['items'];
    if (rawItems is! List || rawItems.length < 2) return;

    final bucketByItem = <Map<String, dynamic>, String>{};
    final existingRows = <int>{};
    final orderedBuckets = <String>[];
    const bucketOrder = <String>[
      'kick',
      'snare_clap',
      'hat',
      'perc',
      'cymbal',
      'tom',
    ];

    for (var itemIndex = 0; itemIndex < rawItems.length; itemIndex += 1) {
      final rawItem = rawItems[itemIndex];
      if (rawItem is! Map) continue;
      final item = rawItem is Map<String, dynamic>
          ? rawItem
          : Map<String, dynamic>.from(rawItem);
      if (!identical(item, rawItem)) {
        rawItems[itemIndex] = item;
      }
      final target = _actionTargetMap(item);
      final libraryPath =
          (item['library_path'] ?? target['library_path'])?.toString().trim() ??
          '';
      final bucket = _drumSampleRowBucket(
        AssistantActionUtils.primarySampleRoleFromText(libraryPath),
      );
      if (bucket == null) continue;
      bucketByItem[item] = bucket;
      if (!orderedBuckets.contains(bucket)) orderedBuckets.add(bucket);
      final rowIndex = _extractNormalizedRowIndex(item, target);
      if (rowIndex != null) existingRows.add(rowIndex);
    }

    if (orderedBuckets.length < 2) return;
    if (existingRows.length > 1) return;

    orderedBuckets.sort((a, b) {
      final ai = bucketOrder.indexOf(a);
      final bi = bucketOrder.indexOf(b);
      return ai.compareTo(bi);
    });

    final baseRow = existingRows.isEmpty
        ? 0
        : existingRows.reduce((a, b) => a < b ? a : b);
    final rowByBucket = <String, int>{
      for (int i = 0; i < orderedBuckets.length; i++)
        orderedBuckets[i]: baseRow + i,
    };

    for (final entry in bucketByItem.entries) {
      final row = rowByBucket[entry.value];
      if (row == null) continue;
      _setSampleInsertItemRow(entry.key, row);
    }
  }

  double? _normalizedProjectTempoBpm(List<Map<String, dynamic>> actions) {
    for (final action in actions) {
      final type = action['type']?.toString().trim().toLowerCase() ?? '';
      if (type != 'project_edit') continue;
      final data = action['data'] as Map<String, dynamic>? ?? const {};
      final operation =
          data['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation != 'set_tempo') continue;
      final tempo = _parseActionDouble(data['tempo_bpm'] ?? data['bpm']);
      if (tempo != null) return tempo;
    }
    return null;
  }

  double? _sampleInsertItemStartBeat(Map<String, dynamic> item) {
    final target = _actionTargetMap(item);
    return _parseActionDouble(
      item['new_start_beat'] ??
          item['paste_start_beat'] ??
          item['start_beat'] ??
          item['at_beat'] ??
          target['new_start_beat'] ??
          target['paste_start_beat'] ??
          target['start_beat'] ??
          target['at_beat'] ??
          item['beat'] ??
          target['beat'] ??
          item['beat_index'] ??
          target['beat_index'],
    );
  }

  double? _sampleInsertItemStepBeats(Map<String, dynamic> item) {
    final target = _actionTargetMap(item);
    return _parseActionDouble(
      item['step_beats'] ??
          target['step_beats'] ??
          item['spacing_beats'] ??
          target['spacing_beats'],
    );
  }

  bool _isRepeatedSampleScaffold(Map<String, dynamic> item) {
    final target = _actionTargetMap(item);
    final repeatCount =
        _parseActionInt(
          item['repeat_count'] ??
              target['repeat_count'] ??
              item['copies'] ??
              target['copies'] ??
              item['count'] ??
              target['count'],
        ) ??
        1;
    return repeatCount > 1 ||
        _hasRepeatingPlacementPayload(item) ||
        _hasMusicalSpanPayload(item);
  }

  bool _sampleInsertItemsShareBeatGrid(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstStart = _sampleInsertItemStartBeat(first) ?? 1.0;
    final secondStart = _sampleInsertItemStartBeat(second) ?? 1.0;
    if ((firstStart - secondStart).abs() > 1e-6) return false;

    final firstStep = _sampleInsertItemStepBeats(first);
    final secondStep = _sampleInsertItemStepBeats(second);
    if (firstStep == null || secondStep == null) {
      return true;
    }
    return (firstStep - secondStep).abs() < 1e-6;
  }

  void _repairBackbeatSampleInsert(
    Map<String, dynamic> data, {
    required double? tempoBpm,
  }) {
    final operation = data['operation']?.toString().trim().toLowerCase() ?? '';
    if (operation != 'insert_audio_clips' && operation != 'insert_audio_clip') {
      return;
    }
    final rawItems = data['items'];
    if (rawItems is! List || rawItems.isEmpty) return;

    final grouped = <String, List<Map<String, dynamic>>>{};
    final kickItems = <Map<String, dynamic>>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = rawItem is Map<String, dynamic>
          ? rawItem
          : Map<String, dynamic>.from(rawItem);
      final target = _actionTargetMap(item);
      final libraryPath =
          (item['library_path'] ?? target['library_path'])?.toString().trim() ??
          '';
      final role = AssistantActionUtils.primarySampleRoleFromText(libraryPath);
      if (role == 'kick') {
        kickItems.add(item);
      }
      if (role != 'snare' && role != 'clap') continue;
      grouped.putIfAbsent(role!, () => <Map<String, dynamic>>[]).add(item);
    }

    for (final roleItems in grouped.values) {
      final repeated = roleItems.where(_isRepeatedSampleScaffold).toList();
      if (repeated.length != 1) continue;

      final item = repeated.single;
      final startBeat = _sampleInsertItemStartBeat(item);
      if (startBeat != null && (startBeat - 1.0).abs() > 1e-6) {
        continue;
      }
      if (_parseActionDouble(
            item['start_ms'] ?? _actionTargetMap(item)['start_ms'],
          ) !=
          null) {
        continue;
      }

      final target = _actionTargetMap(item);
      final explicitStepBeats = _parseActionDouble(
        item['step_beats'] ??
            target['step_beats'] ??
            item['spacing_beats'] ??
            target['spacing_beats'],
      );
      final hasMeasureStep =
          _parseActionDouble(
            item['step_measures'] ??
                target['step_measures'] ??
                item['spacing_measures'] ??
                target['spacing_measures'] ??
                item['step_bars'] ??
                target['step_bars'] ??
                item['spacing_bars'] ??
                target['spacing_bars'],
          ) !=
          null;
      if (hasMeasureStep) {
        continue;
      }

      final collidingKickItems = kickItems
          .where(_isRepeatedSampleScaffold)
          .where((kick) => _sampleInsertItemsShareBeatGrid(item, kick))
          .toList(growable: false);
      if (collidingKickItems.isEmpty) {
        continue;
      }

      final wantsHalfTimeBackbeat =
          tempoBpm != null && tempoBpm >= 135.0 ||
          kickItems.any((kick) {
            final kickStart = _sampleInsertItemStartBeat(kick);
            return kickStart != null && (kickStart - 3.0).abs() < 1e-6;
          });
      item['start_beat'] = wantsHalfTimeBackbeat ? 3 : 2;

      if (explicitStepBeats == null ||
          (explicitStepBeats - 2.0).abs() < 1e-6 ||
          (explicitStepBeats - 4.0).abs() < 1e-6) {
        item['step_beats'] = wantsHalfTimeBackbeat ? 4 : 2;
      }
    }
  }

  String? _extractEffectToken(
    Map<String, dynamic> data,
    Map<String, dynamic> target,
  ) {
    const keys = <String>[
      'effect_name',
      'plugin_name',
      'effect_name_contains',
      'plugin',
      'effect',
      'fx',
      'name',
      'kind',
    ];
    for (final key in keys) {
      final fromData = data[key]?.toString().trim() ?? '';
      if (fromData.isNotEmpty) return fromData;
      final fromTarget = target[key]?.toString().trim() ?? '';
      if (fromTarget.isNotEmpty) return fromTarget;
    }
    return null;
  }

  Map<String, dynamic> _normalizeDawActionData(
    String actionType,
    Map<String, dynamic> rawData,
    String userText,
  ) {
    final data = Map<String, dynamic>.from(rawData);
    final target = _actionTargetMap(data);

    final scopeValue = (data['scope'] ?? target['scope'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (scopeValue != null && scopeValue.isNotEmpty) {
      data['scope'] = scopeValue;
      target['scope'] = scopeValue;
    }

    final rowIndex = _extractNormalizedRowIndex(data, target);
    final isMasterScope =
        (target['scope']?.toString().trim().toLowerCase() ??
            data['scope']?.toString().trim().toLowerCase()) ==
        'master';
    if (!isMasterScope && rowIndex != null) {
      data['row_index'] = rowIndex;
      target['row_index'] = rowIndex;
    }

    if (actionType == 'effect_edit') {
      final effectToken = _extractEffectToken(data, target);
      if (effectToken != null) {
        target.putIfAbsent('effect_name', () => effectToken);
        target.putIfAbsent('plugin_name', () => effectToken);
        target.putIfAbsent('effect_name_contains', () => effectToken);
        data.putIfAbsent('effect_name', () => effectToken);
      }
    }

    if (actionType == 'tutorial') {
      final steps = data['steps'];
      if (steps is List) {
        data['steps'] = steps
            .map((step) {
              if (step is! Map) return step;
              final repaired = Map<String, dynamic>.from(step);
              repaired['target_id'] = _normalizeTutorialTargetId(
                repaired['target_id'],
              );
              return repaired;
            })
            .toList(growable: false);
      }
    }

    if (actionType == 'project_edit') {
      data['operation'] = _normalizeProjectEditOperation(data['operation']);
      final tempo = _parseActionDouble(data['tempo_bpm'] ?? data['bpm']);
      if (tempo != null) {
        data['tempo_bpm'] = tempo;
      }
    }

    if (actionType == 'sample_insert') {
      data['operation'] = _normalizeSampleInsertOperation(data['operation']);
      final rawItems = data['items'];
      if (rawItems is List && rawItems.isNotEmpty) {
        data['items'] = rawItems
            .whereType<Map>()
            .map(
              (raw) =>
                  _normalizeSampleInsertItem(Map<String, dynamic>.from(raw)),
            )
            .toList(growable: false);
      } else if ((data['library_path']?.toString().trim().isNotEmpty ??
              false) ||
          (target['library_path']?.toString().trim().isNotEmpty ?? false)) {
        data['items'] = <Map<String, dynamic>>[
          _normalizeSampleInsertItem(data),
        ];
      }
    }

    if (actionType == 'clip_edit') {
      final operation =
          data['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation == 'pitch_shift' &&
          _parseActionDouble(
                data['semitones'] ??
                    target['semitones'] ??
                    data['delta_semitones'] ??
                    target['delta_semitones'] ??
                    data['pitch_semitones'] ??
                    target['pitch_semitones'] ??
                    data['new_pitch_semitones'] ??
                    target['new_pitch_semitones'],
              ) ==
              null) {
        final text = userText.toLowerCase();
        final oneKey = RegExp(
          r'\b(?:one|1|a)\s+(?:key|semitone|half[- ]step)\b',
        ).hasMatch(text);
        if (oneKey) {
          final direction =
              RegExp(r'\b(lower|down|decrease|drop)\b').hasMatch(text)
              ? -1.0
              : 1.0;
          data['delta_semitones'] = direction;
        }
      }
      if (operation == 'dialog_remove_range' &&
          !_hasCompleteDialogRemoveRangePayload(data)) {
        data['operation'] = 'dialog_remove_range';
      }
    }

    if (actionType == 'role_override') {
      final role = (data['role']?.toString().trim().toLowerCase() ?? '');
      if (role.isNotEmpty) {
        data['role'] = role;
      }
    }

    if (actionType == 'row_group_edit') {
      data['operation'] = _normalizeRowGroupEditOperation(data['operation']);
    }

    if (actionType == 'midi_compose' && data['notes'] is List) {
      data['notes'] = _normalizeMidiNotesPayload(data['notes']);
    }

    if (actionType == 'midi_compose') {
      final operation =
          data['operation']?.toString().trim().toLowerCase() ?? '';
      if (operation == 'replace_notes' &&
          !_hasMidiPayload(data) &&
          _hasMidiLengthPayload(data) &&
          !AssistantActionUtils.hasStyleDrivenMidiGenerationDirectives(
            data,
            target: target,
          )) {
        data['preserve_existing_notes'] = true;
      }
    }

    data['target'] = target;
    return data;
  }

  bool _hasMidiPayload(Map<String, dynamic> data) {
    final notes = data['notes'];
    final progression = data['progression'];
    final hasNotes = notes is List && notes.isNotEmpty;
    final hasProgression =
        (progression is List && progression.isNotEmpty) ||
        (progression is String && progression.trim().isNotEmpty);
    return hasNotes || hasProgression;
  }

  bool _isValidDawActionData(
    String type,
    Map<String, dynamic> data, {
    required String userText,
  }) {
    switch (type) {
      case 'tutorial':
        final topic = data['topic']?.toString().trim() ?? '';
        final steps = data['steps'];
        return topic.isNotEmpty || (steps is List && steps.isNotEmpty);
      case 'clarify':
        final question = data['question']?.toString().trim() ?? '';
        return question.isNotEmpty;
      case 'project_edit':
        return _allowedProjectEditOperations.contains(data['operation']) &&
            _parseActionDouble(data['tempo_bpm'] ?? data['bpm']) != null;
      case 'sample_insert':
        if (!_allowedSampleInsertOperations.contains(data['operation'])) {
          return false;
        }
        final items = data['items'];
        return items is List &&
            items.isNotEmpty &&
            items.whereType<Map>().every((raw) {
              final item = Map<String, dynamic>.from(raw);
              return _isValidSampleInsertItem(
                item,
                operation:
                    data['operation']?.toString().trim().toLowerCase() ?? '',
              );
            });
      case 'clip_edit':
        final operation = data['operation']?.toString().trim().toLowerCase();
        if (!_allowedClipEditOperations.contains(operation)) return false;
        if (operation == 'dialog_remove_range') {
          return _hasCompleteDialogRemoveRangePayload(data);
        }
        if (operation == 'move') {
          return _hasMeaningfulMovePayload(data);
        }
        if (operation == 'cut') {
          return _hasSupportedCutPayload(data);
        }
        if (operation == 'pitch_shift') {
          final target = _actionTargetMap(data);
          return _parseActionDouble(
                data['semitones'] ??
                    target['semitones'] ??
                    data['delta_semitones'] ??
                    target['delta_semitones'] ??
                    data['pitch_semitones'] ??
                    target['pitch_semitones'] ??
                    data['new_pitch_semitones'] ??
                    target['new_pitch_semitones'],
              ) !=
              null;
        }
        return true;
      case 'effect_edit':
        return _allowedEffectEditOperations.contains(data['operation']);
      case 'row_group_edit':
        return _allowedRowGroupEditOperations.contains(data['operation']);
      case 'row_color_edit':
        return _allowedRowColorEditOperations.contains(data['operation']);
      case 'automation_edit':
        if (!_allowedAutomationEditOperations.contains(data['operation'])) {
          return false;
        }
        final operation = data['operation']?.toString().trim().toLowerCase();
        final target = _actionTargetMap(data);
        if (operation == 'apply_template') {
          final template =
              (data['template'] ??
                      target['template'] ??
                      data['pattern'] ??
                      target['pattern'] ??
                      '')
                  .toString();
          if (!_isKnownAutomationTemplate(template)) {
            return false;
          }
        }
        return true;
      case 'midi_compose':
        final operation = data['operation'];
        if (!_allowedMidiComposeOperations.contains(operation)) return false;
        if (operation == 'chop_notes') return true;
        if (operation == 'transpose_notes') {
          return _parseActionDouble(data['semitones']) != null ||
              _parseActionDouble(data['octaves']) != null;
        }
        if (operation == 'convert_audio_to_midi') return true;
        return _hasMidiPayload(data) || _hasPreserveExistingMidiPayload(data);
      case 'stem_separate':
        return _allowedStemSeparateOperations.contains(data['operation']);
      case 'role_override':
        return _allowedRoleOverrideOperations.contains(data['operation']);
      case 'audio_enhance':
        return data['operation'] == 'phone_mic_cleanup';
    }
    return false;
  }

  void _logDroppedDawAction(
    String reason,
    String type,
    Map<String, dynamic> data, {
    required String userText,
  }) {
    final operation = data['operation']?.toString().trim() ?? '';
    aiDebugLog(
      'llm-normalize',
      'dropped daw action reason=$reason type=${type.isEmpty ? "-" : type}'
          ' operation=${operation.isEmpty ? "-" : operation}'
          ' prompt="${userText.trim()}" data=${aiDebugShortMap(data)}',
    );
  }

  List<Map<String, dynamic>> _normalizeDawAssistantActions(
    List rawActions, {
    required String userText,
  }) {
    final out = <Map<String, dynamic>>[];
    var droppedInvalid = false;
    for (final rawAction in rawActions) {
      if (rawAction is! Map) {
        droppedInvalid = true;
        aiDebugLog(
          'llm-normalize',
          'dropped daw action reason=not_map prompt="${userText.trim()}"',
        );
        continue;
      }
      final action = Map<String, dynamic>.from(rawAction);
      final type = (action['type']?.toString().trim().toLowerCase() ?? '');
      if (!_dawAssistantActionTypes.contains(type)) {
        droppedInvalid = true;
        _logDroppedDawAction(
          'unknown_type',
          type,
          Map<String, dynamic>.from(
            action['data'] is Map ? action['data'] as Map : const {},
          ),
          userText: userText,
        );
        continue;
      }
      final rawData = action['data'];
      final data = rawData is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawData)
          : (rawData is Map
                ? Map<String, dynamic>.from(rawData)
                : <String, dynamic>{});
      if (type == 'project_edit') {
        data['operation'] = _normalizeProjectEditOperation(data['operation']);
      } else if (type == 'sample_insert') {
        data['operation'] = _normalizeSampleInsertOperation(data['operation']);
      } else if (type == 'clip_edit') {
        data['operation'] = _normalizeClipEditOperation(data['operation']);
      } else if (type == 'effect_edit') {
        data['operation'] = _normalizeEffectEditOperation(data['operation']);
      } else if (type == 'row_group_edit') {
        data['operation'] = _normalizeRowGroupEditOperation(data['operation']);
      } else if (type == 'row_color_edit') {
        data['operation'] = _normalizeActionToken(data['operation'] ?? 'set');
      } else if (type == 'automation_edit') {
        data['operation'] = _normalizeAutomationEditOperation(
          data['operation'],
        );
      } else if (type == 'midi_compose') {
        data['operation'] = _normalizeMidiComposeOperation(data['operation']);
      } else if (type == 'stem_separate') {
        data['operation'] = _normalizeActionToken(data['operation']);
      } else if (type == 'role_override') {
        data['operation'] = _normalizeRoleOverrideOperation(
          data['operation'] ?? 'set',
        );
      }
      final normalizedData = _normalizeDawActionData(type, data, userText);
      if (!_isValidDawActionData(type, normalizedData, userText: userText)) {
        droppedInvalid = true;
        _logDroppedDawAction(
          'invalid_payload',
          type,
          normalizedData,
          userText: userText,
        );
        continue;
      }
      out.add({'type': type, 'data': normalizedData});
    }
    final normalized = _postProcessNormalizedActions(out);
    if (droppedInvalid &&
        normalized.isNotEmpty &&
        normalized.every(
          (action) =>
              action['type']?.toString().trim().toLowerCase() == 'project_edit',
        )) {
      return const <Map<String, dynamic>>[];
    }
    return normalized;
  }

  Map<String, dynamic>? _decodeToolArgs(dynamic raw) {
    dynamic current = raw;
    for (var i = 0; i < 4; i++) {
      if (current is Map) {
        final map = Map<String, dynamic>.from(current);
        if (map.length == 1 && map.containsKey('value')) {
          current = map['value'];
          continue;
        }
        return map;
      }
      if (current is String) {
        final trimmed = current.trim();
        if (trimmed.isEmpty) return null;
        try {
          current = jsonDecode(trimmed);
        } catch (_) {
          return null;
        }
        continue;
      }
      return null;
    }
    return current is Map ? Map<String, dynamic>.from(current) : null;
  }

  String _normalizeMixExecutionProfile(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'creative_bold':
      case 'experimental_extreme':
        return value;
      case 'producer_safe':
      default:
        return 'producer_safe';
    }
  }

  String _normalizeMixAudibility(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'subtle':
      case 'obvious':
      case 'extreme':
        return value;
      case 'noticeable':
      default:
        return 'noticeable';
    }
  }

  List<String> _normalizeMixStyleTags(dynamic raw) {
    final values = raw is List
        ? raw
        : (raw is String ? <String>[raw] : const <String>[]);
    final out = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      if (normalized.isEmpty || normalized == 'null') continue;
      final canonical = normalized.replaceAll(RegExp(r'\s+'), '_');
      if (canonical.isEmpty || canonical.length > 40) continue;
      if (seen.add(canonical)) {
        out.add(canonical);
      }
      if (out.length >= 8) break;
    }
    return out;
  }

  String _normalizeMixReferenceMode(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'tone':
      case 'loudness':
      case 'width':
      case 'glue':
        return value;
      case 'full_mix':
      default:
        return 'full_mix';
    }
  }

  String _normalizeMixReferenceCloseness(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'loose':
      case 'close':
        return value;
      case 'balanced':
      default:
        return 'balanced';
    }
  }

  Map<String, dynamic>? _normalizeMixReferenceTarget(dynamic raw) {
    if (raw is! Map) return null;
    final normalized = Map<String, dynamic>.from(raw);
    final rowIndex = normalized['row_index'];
    if (rowIndex is num) {
      final canonicalRow = rowIndex.toInt();
      if (canonicalRow < 0) return null;
      normalized
        ..['row_index'] = canonicalRow
        ..remove('prefer_selected');
    } else if (normalized['prefer_selected'] == true) {
      normalized
        ..['prefer_selected'] = true
        ..remove('row_index');
    } else {
      return null;
    }
    normalized['confidence'] = ((normalized['confidence'] ?? 0.5) as num)
        .toDouble()
        .clamp(0.0, 1.0);
    return normalized;
  }

  Map<String, dynamic>? _normalizeToolArgs(
    String toolName,
    dynamic rawArgs, {
    required String userText,
  }) {
    final args = _decodeToolArgs(rawArgs);
    if (args == null) return null;

    if (toolName == 'informational_response') {
      args['message'] = _sanitizeUserFacingText(
        args['message'],
        toolName: toolName,
        userText: userText,
      );
      args['cancels_pending'] = args['cancels_pending'] == true;
      return args;
    }

    if (toolName == 'daw_assistant_actions') {
      final actions = args['actions'];
      if (actions is! List || actions.isEmpty) return null;
      final normalizedActions = _normalizeDawAssistantActions(
        actions,
        userText: userText,
      );
      if (normalizedActions.isEmpty) return null;
      final assistantMessage = _sanitizeUserFacingText(
        args['assistant_message'],
        toolName: toolName,
        userText: userText,
        allowFallback: false,
      );
      args['actions'] = normalizedActions;
      args['assistant_message'] = assistantMessage;
      return args;
    }

    if (toolName == 'mix_model_request') {
      final actions = args['actions'];
      final mode = (args['mode']?.toString() ?? '').trim();
      if (actions is! List || actions.isEmpty) return null;
      if (mode != 'execute' && mode != 'propose') return null;

      for (final action in actions) {
        if (action is! Map) return null;
        final goal = action['goal'];
        if (goal is! Map) return null;
        final normalizedGoal = Map<String, dynamic>.from(goal);
        normalizedGoal['type'] = 'mix_request';
        normalizedGoal['execution_profile'] = _normalizeMixExecutionProfile(
          normalizedGoal['execution_profile'],
        );
        normalizedGoal['audibility'] = _normalizeMixAudibility(
          normalizedGoal['audibility'],
        );
        normalizedGoal['style_tags'] = _normalizeMixStyleTags(
          normalizedGoal['style_tags'],
        );
        normalizedGoal['destructive_ok'] =
            normalizedGoal['destructive_ok'] == true;
        final normalizedReferenceTarget = _normalizeMixReferenceTarget(
          normalizedGoal['reference_target'],
        );
        if (normalizedReferenceTarget != null) {
          normalizedGoal['reference_target'] = normalizedReferenceTarget;
          normalizedGoal['reference_mode'] = _normalizeMixReferenceMode(
            normalizedGoal['reference_mode'],
          );
          normalizedGoal['reference_closeness'] =
              _normalizeMixReferenceCloseness(
                normalizedGoal['reference_closeness'],
              );
        } else {
          normalizedGoal.remove('reference_target');
          normalizedGoal.remove('reference_mode');
          normalizedGoal.remove('reference_closeness');
        }
        final target = normalizedGoal['target'];
        if (target is! Map) return null;

        final normalizedTarget = Map<String, dynamic>.from(target);
        final scope = (normalizedTarget['scope']?.toString() ?? '').trim();
        if (scope == 'master') {
          normalizedTarget.remove('row_index');
          normalizedTarget.remove('role');
        } else {
          final rowIndex = normalizedTarget['row_index'];
          if (rowIndex is num) {
            final normalizedRow = rowIndex.toInt();
            if (normalizedRow < 0) return null;
            normalizedTarget['row_index'] = normalizedRow;
          } else if (rowIndex != null) {
            return null;
          }
        }
        normalizedGoal['target'] = normalizedTarget;

        final intents = normalizedGoal['intents'];
        if (intents is! List || intents.isEmpty) return null;
        for (final intent in intents) {
          if (intent is! Map) return null;
        }
        action['goal'] = normalizedGoal;
      }

      final assistantMessage = _sanitizeUserFacingText(
        args['assistant_message'],
        toolName: toolName,
        userText: userText,
        allowFallback: false,
      );
      args['assistant_message'] = assistantMessage;
      return args;
    }

    return args;
  }

  Future<LlmResult> send({
    required List<Map<String, String>> conversation,
    required String userText,
    required String projectSnapshot,
    String selectionSnapshot = '',
    String librarySnapshot = '',
    String? promptTraceId,
    String? projectId,
    String? aiFeature,
    String? conversationSessionId,
    MixingResult? pendingMix,
    Map<String, dynamic> clientContext = const <String, dynamic>{},
  }) async {
    final requestStopwatch = Stopwatch();
    final parseStopwatch = Stopwatch();
    var directRetriedWithoutPendingMix = false;
    late http.Response response;
    try {
      if (_isProxyEnabled) {
        final token = await _resolveProxyAuthToken();
        if (token == null || token.isEmpty) {
          return _recoverableTextResult(
            _recoverableAuthMessage,
            softErrorCode: 'auth_unavailable',
          );
        }

        requestStopwatch.start();
        response = await _postProxyJson(
          token: token,
          conversation: conversation,
          userText: userText,
          projectSnapshot: projectSnapshot,
          selectionSnapshot: selectionSnapshot,
          librarySnapshot: librarySnapshot,
          promptTraceId: promptTraceId,
          projectId: projectId,
          aiFeature: aiFeature,
          conversationSessionId: conversationSessionId,
          pendingMix: pendingMix,
          clientContext: clientContext,
        );
        requestStopwatch.stop();
      } else if (_canUseDirectOpenAi) {
        if (!_isUsingDebugSystemPrompt) {
          return LlmResult.text(
            'Direct OpenAI debug mode requires a non-empty kDebugSystemPrompt in lib/ai/debug_system_prompt.dart.',
            null,
          );
        }
        final effectiveClientContext = _mergedAnalyticsClientContext(
          clientContext,
        );
        final packedContext = _packContextSnapshots(
          mode: _readContextPackingMode(effectiveClientContext),
          projectSnapshot: projectSnapshot,
          selectionSnapshot: selectionSnapshot,
          librarySnapshot: librarySnapshot,
        );
        final normalizedSessionId =
            (conversationSessionId ?? '').trim().isNotEmpty
            ? conversationSessionId!.trim()
            : 'direct-debug-session';
        final conversationKey = _directConversationKey(
          sessionId: normalizedSessionId,
          aiFeature: aiFeature,
          clientContext: effectiveClientContext,
        );
        final directClientCapabilities = _readClientCapabilities(
          effectiveClientContext,
        );
        final directClientPolicy = _readClientPolicy(effectiveClientContext);
        final directInstructionOverlay = aiExecutionGuidance();
        final directSeedInstructions = _buildDirectSeedInstructions(
          clientCapabilities: directClientCapabilities,
          clientPolicy: directClientPolicy,
          instructionOverlay: directInstructionOverlay,
        );
        final directSeedHash = _conversationSeedHash(directSeedInstructions);
        final directSeedItems = _usesSeededOpenAiConversationState
            ? _buildOpenAiConversationSeedItems(
                seedInstructions: directSeedInstructions,
              )
            : const <Map<String, dynamic>>[];
        final directConversationId = _usesOpenAiConversationState
            ? await _ensureDirectOpenAiConversation(
                conversationKey,
                seedItems: directSeedItems,
                seedHash: _usesSeededOpenAiConversationState
                    ? directSeedHash
                    : '',
              )
            : null;
        final inputMessages = _usesOpenAiConversationState
            ? <Map<String, dynamic>>[
                <String, dynamic>{'role': 'user', 'content': userText},
              ]
            : _buildInputMessages(
                conversation: conversation,
                userText: userText,
                projectSnapshot: packedContext.projectSnapshot,
                selectionSnapshot: packedContext.selectionSnapshot,
                librarySnapshot: packedContext.librarySnapshot,
                pendingMix: pendingMix,
              );
        final conversationContext = _usesOpenAiConversationState
            ? _buildConversationContextInstructions(
                projectSnapshot: packedContext.projectSnapshot,
                selectionSnapshot: packedContext.selectionSnapshot,
                librarySnapshot: packedContext.librarySnapshot,
                pendingMix: pendingMix,
              )
            : '';

        final requestBody = _buildOpenAiRequestBody(
          inputMessages: inputMessages,
          userText: userText,
          aiFeature: aiFeature,
          clientContext: effectiveClientContext,
          conversationId: directConversationId,
          conversationContextInstructions: conversationContext,
          seededConversation: _usesSeededOpenAiConversationState,
          seededConversationInstructionHash: directSeedHash,
        );
        aiDebugLog(
          'direct-openai',
          'request route=$_llmRouteLabel model=${model.trim()} '
              'reasoning=${requestBody['reasoning']} '
              'tool_choice=${requestBody['tool_choice']} '
              'tool_count=${(requestBody['tools'] as List?)?.length ?? 0} '
              'prompt_cache_key=${requestBody['prompt_cache_key']} '
              'prompt_cache_retention=${requestBody['prompt_cache_retention']} '
              'conversation_state=$_normalizedConversationStateMode '
              'conversation_id=${directConversationId ?? '-'}',
        );
        _debugDumpJson('direct-openai', 'request body', requestBody);

        final hasLibrarySnapshot = librarySnapshot.trim().isNotEmpty;
        final hasRetryDroppableContext = pendingMix != null;
        final initialTimeout = hasRetryDroppableContext
            ? Duration(
                milliseconds: math.min(requestTimeout.inMilliseconds, 12000),
              )
            : requestTimeout;

        requestStopwatch.start();
        try {
          response = await _postJson(
            uri: Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: requestBody,
            timeoutOverride: initialTimeout,
          );
          requestStopwatch.stop();
        } on TimeoutException {
          requestStopwatch.stop();
          final canRetryWithoutHeavyContext =
              hasRetryDroppableContext &&
              initialTimeout.inMilliseconds < requestTimeout.inMilliseconds;
          if (!canRetryWithoutHeavyContext) rethrow;

          directRetriedWithoutPendingMix = true;
          final remainingTimeout = Duration(
            milliseconds: math.max(
              4000,
              requestTimeout.inMilliseconds - initialTimeout.inMilliseconds,
            ),
          );
          aiDebugLog(
            'direct-openai',
            'request timeout -> retrying without pending mix '
                '(library_retained=$hasLibrarySnapshot, '
                'retry_timeout_ms=${remainingTimeout.inMilliseconds})',
          );
          final retryInputMessages = _usesOpenAiConversationState
              ? <Map<String, dynamic>>[
                  <String, dynamic>{'role': 'user', 'content': userText},
                ]
              : _buildInputMessages(
                  conversation: conversation,
                  userText: userText,
                  projectSnapshot: packedContext.projectSnapshot,
                  selectionSnapshot: packedContext.selectionSnapshot,
                  librarySnapshot: packedContext.librarySnapshot,
                  pendingMix: null,
                );
          final retryRequestBody = _buildOpenAiRequestBody(
            inputMessages: retryInputMessages,
            userText: userText,
            aiFeature: aiFeature,
            clientContext: effectiveClientContext,
            conversationId: directConversationId,
            conversationContextInstructions: _usesOpenAiConversationState
                ? _buildConversationContextInstructions(
                    projectSnapshot: packedContext.projectSnapshot,
                    selectionSnapshot: packedContext.selectionSnapshot,
                    librarySnapshot: packedContext.librarySnapshot,
                    pendingMix: null,
                  )
                : '',
            seededConversation: _usesSeededOpenAiConversationState,
            seededConversationInstructionHash: directSeedHash,
          );
          _debugDumpJson(
            'direct-openai',
            'retry request body',
            retryRequestBody,
          );
          requestStopwatch
            ..reset()
            ..start();
          response = await _postJson(
            uri: Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: retryRequestBody,
            timeoutOverride: remainingTimeout,
          );
          requestStopwatch.stop();
        }
      } else {
        return LlmResult.text(
          'AI is not configured. Launch with --dart-define=LLM_PROXY_API_BASE_URL=... or --dart-define=OPENAI_API_KEY=... --dart-define=OPENAI_MODEL=...',
          null,
        );
      }
    } catch (error, stackTrace) {
      aiDebugLog(
        'llm-request',
        'request failed before parse: $error\n$stackTrace',
      );
      return _recoverableTextResult(
        _temporaryFailureMessage,
        softErrorCode: 'request_failed',
      );
    }

    parseStopwatch.start();
    var payload = _decodeJsonObject(response.body);
    var responseMeta = _buildResponseMeta(payload);
    responseMeta = _mergeMetaObservability(responseMeta, <String, dynamic>{
      if ((promptTraceId ?? '').trim().isNotEmpty)
        'prompt_trace_id': promptTraceId!.trim(),
      'proxy_roundtrip_ms': requestStopwatch.elapsedMilliseconds,
      'http_status_code': response.statusCode,
      'llm_route': _llmRouteLabel,
      'prompt_source': _promptSourceLabel,
      'conversation_state_mode_requested': _normalizedConversationStateMode,
      'conversation_state_mode_effective': _usesOpenAiConversationState
          ? _normalizedConversationStateMode
          : 'manual_history',
      'context_packing_mode': _readContextPackingMode(clientContext),
      'tool_routing_mode': _readToolRoutingMode(clientContext),
      'effective_tool_routing_mode': _effectiveToolRoutingMode(clientContext),
      if ((conversationSessionId ?? '').trim().isNotEmpty)
        'conversation_session_id': conversationSessionId!.trim(),
      if (!_isProxyEnabled && _canUseDirectOpenAi) ...<String, dynamic>{
        'provider': 'openai',
        'effective_model': model.trim(),
        if (_usesOpenAiConversationState)
          'conversation_turn_index':
              _conversationTurnCounts[_directConversationKey(
                sessionId: (conversationSessionId ?? '').trim().isNotEmpty
                    ? conversationSessionId!.trim()
                    : 'direct-debug-session',
                aiFeature: aiFeature,
                clientContext: _mergedAnalyticsClientContext(clientContext),
              )] ??
              0,
        if (directRetriedWithoutPendingMix)
          'direct_retry_without_pending_mix': true,
      },
    });
    var promptRateLimit = _parsePromptRateLimitStatus(
      payload?['prompt_rate_limit'],
    );
    parseStopwatch.stop();
    responseMeta = _mergeMetaObservability(responseMeta, <String, dynamic>{
      'response_parse_ms': parseStopwatch.elapsedMilliseconds,
    });

    if (!_isProxyEnabled && response.statusCode != 200) {
      aiDebugLog(
        'direct-openai',
        'error status=${response.statusCode} body=${payload ?? response.body}',
      );
    }
    if (!_isProxyEnabled && kAiDebugLogs) {
      aiDebugLog(
        'direct-openai',
        'response status=${response.statusCode} '
            'output_count=${(payload?['output'] as List?)?.length ?? 0}',
      );
      _debugDumpRawBody('direct-openai', 'response body', response.body);
    }

    if (response.statusCode != 200) {
      if (_isPromptRateLimitResponse(
        response.statusCode,
        payload,
        promptRateLimit,
      )) {
        final message = _rateLimitMessage(
          promptRateLimit,
          payload?['message']?.toString().trim().isNotEmpty == true
              ? payload!['message'].toString().trim()
              : 'You have reached the prompt limit. Please try again later.',
        );
        final rateLimitMeta = <String, dynamic>{
          ...responseMeta,
          if (promptRateLimit != null)
            'prompt_rate_limit': promptRateLimit.toJson(),
          'prompt_rate_limit_hit': true,
        };
        return LlmResult.text(message, {
          'message': message,
          'cancels_pending': false,
        }, meta: rateLimitMeta);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (_isProxyEnabled && refreshAuthTokenProvider != null) {
          try {
            final refreshedToken = await _resolveProxyAuthToken(
              forceRefresh: true,
            );
            if (refreshedToken != null && refreshedToken.isNotEmpty) {
              requestStopwatch
                ..reset()
                ..start();
              response = await _postProxyJson(
                token: refreshedToken,
                conversation: conversation,
                userText: userText,
                projectSnapshot: projectSnapshot,
                selectionSnapshot: selectionSnapshot,
                librarySnapshot: librarySnapshot,
                promptTraceId: promptTraceId,
                projectId: projectId,
                aiFeature: aiFeature,
                conversationSessionId: conversationSessionId,
                pendingMix: pendingMix,
                clientContext: clientContext,
              );
              requestStopwatch.stop();
              parseStopwatch
                ..reset()
                ..start();
              payload = _decodeJsonObject(response.body);
              responseMeta = _buildResponseMeta(payload);
              responseMeta =
                  _mergeMetaObservability(responseMeta, <String, dynamic>{
                    if ((promptTraceId ?? '').trim().isNotEmpty)
                      'prompt_trace_id': promptTraceId!.trim(),
                    'proxy_roundtrip_ms': requestStopwatch.elapsedMilliseconds,
                    'http_status_code': response.statusCode,
                    'llm_route': _llmRouteLabel,
                    'prompt_source': _promptSourceLabel,
                    'conversation_state_mode_requested':
                        _normalizedConversationStateMode,
                    'conversation_state_mode_effective':
                        _usesOpenAiConversationState
                        ? _normalizedConversationStateMode
                        : 'manual_history',
                    'context_packing_mode': _readContextPackingMode(
                      clientContext,
                    ),
                    'tool_routing_mode': _readToolRoutingMode(clientContext),
                    'effective_tool_routing_mode': _effectiveToolRoutingMode(
                      clientContext,
                    ),
                    if ((conversationSessionId ?? '').trim().isNotEmpty)
                      'conversation_session_id': conversationSessionId!.trim(),
                  });
              promptRateLimit = _parsePromptRateLimitStatus(
                payload?['prompt_rate_limit'],
              );
              parseStopwatch.stop();
              responseMeta = _mergeMetaObservability(
                responseMeta,
                <String, dynamic>{
                  'response_parse_ms': parseStopwatch.elapsedMilliseconds,
                },
              );
              if (response.statusCode == 200) {
                // Continue into the normal response parsing below.
              } else if (_isPromptRateLimitResponse(
                response.statusCode,
                payload,
                promptRateLimit,
              )) {
                final message = _rateLimitMessage(
                  promptRateLimit,
                  payload?['message']?.toString().trim().isNotEmpty == true
                      ? payload!['message'].toString().trim()
                      : 'You have reached the prompt limit. Please try again later.',
                );
                return LlmResult.text(message, {
                  'message': message,
                  'cancels_pending': false,
                }, meta: responseMeta);
              } else if (response.statusCode == 401 ||
                  response.statusCode == 403) {
                return _recoverableTextResult(
                  _recoverableAuthMessage,
                  softErrorCode: 'auth_rejected',
                  meta: responseMeta,
                );
              } else {
                return _recoverableTextResult(
                  _temporaryFailureMessage,
                  softErrorCode: 'request_failed',
                  meta: responseMeta,
                );
              }
            }
          } catch (_) {
            // Fall through to the recoverable auth message below.
          }
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          return _recoverableTextResult(
            _recoverableAuthMessage,
            softErrorCode: 'auth_rejected',
            meta: responseMeta,
          );
        }
      }
      if (response.statusCode != 200) {
        return _recoverableTextResult(
          _temporaryFailureMessage,
          softErrorCode: 'request_failed',
          meta: responseMeta,
        );
      }
    }
    final json = payload ?? const <String, dynamic>{};
    final outputs = (json['output'] as List<dynamic>? ?? const []);

    final List<LlmResult> toolResults = [];
    String? assistantText;

    for (final o in outputs) {
      final type = o['type'];

      if (type == 'function_call') {
        final name = o['name'] as String?;
        if (name == null) continue;

        final args = _normalizeToolArgs(
          name,
          o['arguments'],
          userText: userText,
        );
        if (args == null) {
          aiDebugLog(
            'llm-parse',
            'invalid function_call name=$name raw_args=${o['arguments']}',
          );
          final fallbackText = _invalidToolCallFallbackText(
            name,
            o['arguments'],
            userText: userText,
          );
          return LlmResult.text(fallbackText, <String, dynamic>{
            'message': fallbackText,
          }, meta: responseMeta);
        }
        aiDebugLog(
          'llm-parse',
          'function_call name=$name args=${aiDebugShortMap(args)}',
        );
        _debugDumpJson('llm-parse', 'normalized args for $name', args);
        toolResults.add(
          name == 'informational_response'
              ? LlmResult.text(
                  args['message']?.toString() ?? '',
                  args,
                  meta: responseMeta,
                )
              : LlmResult.tool(
                  name,
                  args,
                  text: args['assistant_message'],
                  meta: responseMeta,
                ),
        );
        continue;
      }

      // 2️⃣ Message outputs
      if (type == 'message') {
        final content = o['content'];
        if (content is! List) continue;

        for (final c in content) {
          if (c is! Map || c['type'] != 'output_text') continue;

          final text = c['text'];

          // ✅ CRITICAL FIX:
          // If the model emitted a structured object, treat it as a tool call
          if (text is Map<String, dynamic>) {
            final args = _normalizeToolArgs(
              'mix_model_request',
              text,
              userText: userText,
            );
            if (args == null) {
              final fallbackText = _invalidToolCallFallbackText(
                'mix_model_request',
                text,
                userText: userText,
              );
              return LlmResult.text(fallbackText, <String, dynamic>{
                'message': fallbackText,
              }, meta: responseMeta);
            }
            toolResults.add(
              LlmResult.tool('mix_model_request', args, meta: responseMeta),
            );
            continue;
          }

          // Normal assistant text
          if (text is String &&
              text.trim().isNotEmpty &&
              assistantText == null) {
            assistantText = _sanitizeUserFacingText(
              text,
              toolName: 'informational_response',
              userText: userText,
            );
          }
        }
      }
    }

    if (toolResults.isNotEmpty) {
      final informationalResults = toolResults.where(
        (t) => t.toolName == 'informational_response',
      );
      final nonInformationalResults = toolResults.where(
        (t) => t.toolName != 'informational_response',
      );

      if (nonInformationalResults.isEmpty) {
        final firstInfo = informationalResults.first;
        return LlmResult.text(
          firstInfo.text ?? '',
          firstInfo.toolArgs,
          meta: responseMeta,
        );
      }

      final firstTool = nonInformationalResults.first;
      final sameToolType = nonInformationalResults.every(
        (t) => t.toolName == firstTool.toolName,
      );
      if (!sameToolType) {
        final dawResults = nonInformationalResults
            .where((t) => t.toolName == 'daw_assistant_actions')
            .toList(growable: false);
        final mixResults = nonInformationalResults
            .where((t) => t.toolName == 'mix_model_request')
            .toList(growable: false);
        final preferredResults = dawResults.isNotEmpty
            ? dawResults
            : mixResults;
        if (preferredResults.isNotEmpty) {
          final preferredTool = preferredResults.first.toolName!;
          final preferredArgs = preferredResults
              .map((t) => t.toolArgs)
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          final userFacingText =
              assistantText ??
              preferredResults
                  .map((t) => t.text?.trim() ?? '')
                  .firstWhere((t) => t.isNotEmpty, orElse: () => '');
          final mixedMeta = <String, dynamic>{
            ...responseMeta,
            'mixed_tool_fallback': true,
            'mixed_tool_names': nonInformationalResults
                .map((t) => t.toolName)
                .whereType<String>()
                .toList(growable: false),
          };
          return LlmResult.tool(
            preferredTool,
            preferredArgs.length == 1
                ? preferredArgs.first
                : <String, dynamic>{'calls': preferredArgs},
            text: userFacingText.isEmpty ? null : userFacingText,
            meta: mixedMeta,
          );
        }
        return LlmResult.text(
          _fallbackAssistantText('informational_response'),
          {
            'message': _fallbackAssistantText('informational_response'),
            'cancels_pending': false,
          },
          meta: responseMeta,
        );
      }

      final callArgs = nonInformationalResults
          .map((t) => t.toolArgs)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      final userFacingText =
          assistantText ??
          nonInformationalResults
              .map((t) => t.text?.trim() ?? '')
              .firstWhere((t) => t.isNotEmpty, orElse: () => '');

      if (callArgs.length == 1) {
        return LlmResult.tool(
          firstTool.toolName!,
          callArgs.first,
          text: userFacingText.isEmpty ? null : userFacingText,
          meta: responseMeta,
        );
      }

      return LlmResult.tool(
        firstTool.toolName!,
        {'calls': callArgs},
        text: userFacingText.isEmpty ? null : userFacingText,
        meta: responseMeta,
      );
    }

    // Only reach here if NO tool-like structure existed
    if (assistantText != null &&
        assistantText != _fallbackAssistantText('informational_response')) {
      return LlmResult.text(assistantText, null, meta: responseMeta);
    }

    return LlmResult.text(_fallbackAssistantText('informational_response'), {
      'message': _fallbackAssistantText('informational_response'),
      'cancels_pending': false,
    }, meta: responseMeta);
  }
}
