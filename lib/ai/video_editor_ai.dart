import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/helpers/video_sequencer_engine.dart';
import 'package:path/path.dart' as p;

class VideoEditorAiAction {
  const VideoEditorAiAction({
    required this.type,
    required this.data,
  });

  final String type;
  final Map<String, dynamic> data;

  factory VideoEditorAiAction.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return VideoEditorAiAction(
      type: (json['type'] as String?)?.trim() ?? '',
      data: rawData is Map<String, dynamic>
          ? rawData
          : (rawData is Map ? Map<String, dynamic>.from(rawData) : const {}),
    );
  }
}

class VideoEditorAiResponse {
  const VideoEditorAiResponse({
    required this.message,
    this.actions = const <VideoEditorAiAction>[],
    this.usedFallback = false,
  });

  final String message;
  final List<VideoEditorAiAction> actions;
  final bool usedFallback;

  bool get hasActions => actions.isNotEmpty;
}

class VideoEditorAiProjectSnapshot {
  const VideoEditorAiProjectSnapshot({
    required this.projectId,
    required this.projectName,
    required this.playheadMs,
    required this.pixelsPerSecond,
    required this.tracks,
    required this.transitions,
    this.selectedClipId,
    this.selectedTransitionId,
  });

  final String projectId;
  final String projectName;
  final int playheadMs;
  final double pixelsPerSecond;
  final List<VideoEditorAiTrackSnapshot> tracks;
  final List<VideoEditorAiTransitionSnapshot> transitions;
  final String? selectedClipId;
  final String? selectedTransitionId;

  static String _safeSourceName(
    String rawPath, {
    required String fallbackLabel,
  }) {
    final trimmedPath = rawPath.trim();
    if (trimmedPath.isEmpty) {
      return fallbackLabel.trim();
    }

    final fileName = p.basename(trimmedPath).trim();
    if (fileName.isNotEmpty) {
      return fileName;
    }
    return fallbackLabel.trim();
  }

  factory VideoEditorAiProjectSnapshot.fromSequencer({
    required String projectId,
    required String projectName,
    required VideoSequencerEngine engine,
    String? selectedTransitionId,
  }) {
    final tracks = <VideoEditorAiTrackSnapshot>[];
    final transitions = engine.videoTransitions
        .map(
          (transition) => VideoEditorAiTransitionSnapshot(
            id: transition.id,
            fromClipId: transition.fromClipId,
            toClipId: transition.toClipId,
            durationMs: transition.duration.inMilliseconds,
            type: transition.type.name,
          ),
        )
        .toList(growable: false);

    for (int trackIndex = 0; trackIndex < engine.tracks.length; trackIndex++) {
      final track = engine.tracks[trackIndex];
      final clips = <VideoEditorAiClipSnapshot>[];
      for (int clipIndex = 0; clipIndex < track.clips.length; clipIndex++) {
        final clip = track.clips[clipIndex];
        clips.add(
          VideoEditorAiClipSnapshot(
            id: clip.id,
            trackId: track.id,
            trackIndex: trackIndex,
            clipIndex: clipIndex,
            trackType: clip.trackType.name,
            label: clip.label,
            sourceName: _safeSourceName(
              clip.sourcePath,
              fallbackLabel: clip.label,
            ),
            timelineStartMs: clip.timelineStart.inMilliseconds,
            timelineEndMs: clip.timelineEnd.inMilliseconds,
            sourceStartMs: clip.sourceStart.inMilliseconds,
            sourceDurationMs: clip.sourceDuration.inMilliseconds,
            sourceTotalDurationMs: clip.sourceTotalDuration.inMilliseconds,
            volume: clip.volume,
            muted: clip.muted,
          ),
        );
      }

      tracks.add(
        VideoEditorAiTrackSnapshot(
          id: track.id,
          index: trackIndex,
          type: track.type.name,
          name: track.name,
          muted: track.muted,
          solo: track.solo,
          clips: clips,
        ),
      );
    }

    return VideoEditorAiProjectSnapshot(
      projectId: projectId,
      projectName: projectName,
      playheadMs: engine.playhead.inMilliseconds,
      pixelsPerSecond: engine.pixelsPerSecond,
      tracks: tracks,
      transitions: transitions,
      selectedClipId: engine.selectedClipId,
      selectedTransitionId: selectedTransitionId,
    );
  }

  Iterable<VideoEditorAiClipSnapshot> get allClips sync* {
    for (final track in tracks) {
      for (final clip in track.clips) {
        yield clip;
      }
    }
  }

  List<VideoEditorAiClipSnapshot> allClipsSorted({
    String? trackType,
  }) {
    final filtered = allClips
        .where((clip) => trackType == null || clip.trackType == trackType)
        .toList(growable: false);
    filtered.sort((a, b) {
      final startCompare = a.timelineStartMs.compareTo(b.timelineStartMs);
      if (startCompare != 0) return startCompare;
      final trackCompare = a.trackIndex.compareTo(b.trackIndex);
      if (trackCompare != 0) return trackCompare;
      return a.clipIndex.compareTo(b.clipIndex);
    });
    return filtered;
  }

  VideoEditorAiClipSnapshot? clipById(String? clipId) {
    if ((clipId ?? '').trim().isEmpty) return null;
    for (final clip in allClips) {
      if (clip.id == clipId) return clip;
    }
    return null;
  }

  VideoEditorAiTransitionSnapshot? transitionById(String? transitionId) {
    if ((transitionId ?? '').trim().isEmpty) return null;
    for (final transition in transitions) {
      if (transition.id == transitionId) return transition;
    }
    return null;
  }

  VideoEditorAiClipSnapshot? get selectedClip => clipById(selectedClipId);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'project_id': projectId,
      'project_name': projectName,
      'playhead_ms': playheadMs,
      'pixels_per_second': pixelsPerSecond,
      'selected_clip_id': selectedClipId,
      'selected_transition_id': selectedTransitionId,
      'tracks': tracks.map((track) => track.toJson()).toList(),
      'transitions':
          transitions.map((transition) => transition.toJson()).toList(),
    };
  }

  String toPromptSnapshot() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String toSelectionSnapshot() {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'playhead_ms': playheadMs,
      'selected_clip_id': selectedClipId,
      'selected_transition_id': selectedTransitionId,
    });
  }
}

class VideoEditorAiTrackSnapshot {
  const VideoEditorAiTrackSnapshot({
    required this.id,
    required this.index,
    required this.type,
    required this.name,
    required this.muted,
    required this.solo,
    required this.clips,
  });

  final String id;
  final int index;
  final String type;
  final String name;
  final bool muted;
  final bool solo;
  final List<VideoEditorAiClipSnapshot> clips;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'index': index,
      'type': type,
      'name': name,
      'muted': muted,
      'solo': solo,
      'clips': clips.map((clip) => clip.toJson()).toList(),
    };
  }
}

class VideoEditorAiClipSnapshot {
  const VideoEditorAiClipSnapshot({
    required this.id,
    required this.trackId,
    required this.trackIndex,
    required this.clipIndex,
    required this.trackType,
    required this.label,
    required this.sourceName,
    required this.timelineStartMs,
    required this.timelineEndMs,
    required this.sourceStartMs,
    required this.sourceDurationMs,
    required this.sourceTotalDurationMs,
    required this.volume,
    required this.muted,
  });

  final String id;
  final String trackId;
  final int trackIndex;
  final int clipIndex;
  final String trackType;
  final String label;
  final String sourceName;
  final int timelineStartMs;
  final int timelineEndMs;
  final int sourceStartMs;
  final int sourceDurationMs;
  final int sourceTotalDurationMs;
  final double volume;
  final bool muted;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'track_id': trackId,
      'track_index': trackIndex,
      'clip_index': clipIndex,
      'track_type': trackType,
      'label': label,
      'source_name': sourceName,
      'timeline_start_ms': timelineStartMs,
      'timeline_end_ms': timelineEndMs,
      'source_start_ms': sourceStartMs,
      'source_duration_ms': sourceDurationMs,
      'source_total_duration_ms': sourceTotalDurationMs,
      'volume': volume,
      'muted': muted,
    };
  }
}

class VideoEditorAiTransitionSnapshot {
  const VideoEditorAiTransitionSnapshot({
    required this.id,
    required this.fromClipId,
    required this.toClipId,
    required this.durationMs,
    required this.type,
  });

  final String id;
  final String fromClipId;
  final String toClipId;
  final int durationMs;
  final String type;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'from_clip_id': fromClipId,
      'to_clip_id': toClipId,
      'duration_ms': durationMs,
      'type': type,
    };
  }
}

class VideoEditorAiService {
  static const String _videoAiFeature = 'video_editor_chat';
  static const String _apiUrl = 'https://api.openai.com/v1/responses';

  VideoEditorAiService({
    required this.apiKey,
    required this.model,
    required this.proxyApiBaseUrl,
    required this.proxyPath,
    this.authTokenProvider,
    this.refreshAuthTokenProvider,
    this.requestTimeout = const Duration(seconds: 20),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final String model;
  final String proxyApiBaseUrl;
  final String proxyPath;
  final Future<String?> Function()? authTokenProvider;
  final Future<String?> Function()? refreshAuthTokenProvider;
  final Duration requestTimeout;
  final http.Client _httpClient;

  bool get _isProxyEnabled => proxyApiBaseUrl.trim().isNotEmpty;
  bool get _canUseDirectOpenAi =>
      apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  Future<VideoEditorAiResponse> handleUserText({
    required String userText,
    required VideoEditorAiProjectSnapshot snapshot,
    required List<Map<String, String>> conversation,
  }) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      return const VideoEditorAiResponse(
        message: 'Tell me what you want to change in the timeline.',
        usedFallback: true,
      );
    }

    if (_isProxyEnabled || _canUseDirectOpenAi) {
      final remote = await _sendRemote(
        userText: trimmed,
        snapshot: snapshot,
        conversation: conversation,
      );
      if (remote != null) {
        return remote;
      }
    }

    return const VideoEditorAiResponse(
      message: "I couldn't reach the AI service just now. Please try again.",
      usedFallback: true,
    );
  }

  Future<VideoEditorAiResponse?> _sendRemote({
    required String userText,
    required VideoEditorAiProjectSnapshot snapshot,
    required List<Map<String, String>> conversation,
  }) async {
    late http.Response response;
    try {
      if (_isProxyEnabled) {
        final token = await _resolveProxyAuthToken();
        if (token == null || token.isEmpty) {
          return null;
        }
        response = await _postProxyRequest(
          token: token,
          userText: userText,
          snapshot: snapshot,
          conversation: conversation,
        );
      } else if (_canUseDirectOpenAi) {
        response = await _httpClient
            .post(
              Uri.parse(_apiUrl),
              headers: <String, String>{
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(
                _buildOpenAiBody(
                  userText: userText,
                  snapshot: snapshot,
                  conversation: conversation,
                ),
              ),
            )
            .timeout(requestTimeout);
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }

    if ((response.statusCode == 401 || response.statusCode == 403) &&
        _isProxyEnabled &&
        refreshAuthTokenProvider != null) {
      try {
        final refreshedToken =
            await _resolveProxyAuthToken(forceRefresh: true);
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          response = await _postProxyRequest(
            token: refreshedToken,
            userText: userText,
            snapshot: snapshot,
            conversation: conversation,
          );
        }
      } catch (_) {
        return null;
      }
    }

    if (response.statusCode != 200) {
      return null;
    }

    try {
      final json = jsonDecode(response.body);
      return _parseResponsePayload(json);
    } catch (_) {
      return null;
    }
  }

  Uri _resolveProxyUri() {
    final base = proxyApiBaseUrl.trim();
    final path = proxyPath.trim().isEmpty ? '/v1/llm/responses' : proxyPath;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalizedPath');
  }

  Future<String?> _resolveProxyAuthToken({bool forceRefresh = false}) async {
    final primaryProvider =
        forceRefresh ? refreshAuthTokenProvider : authTokenProvider;
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

  Future<http.Response> _postProxyRequest({
    required String token,
    required String userText,
    required VideoEditorAiProjectSnapshot snapshot,
    required List<Map<String, String>> conversation,
  }) {
    return _httpClient
        .post(
          _resolveProxyUri(),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(
            <String, dynamic>{
              'conversation': conversation
                  .map(
                    (message) => <String, dynamic>{
                      'role': message['role'],
                      'content': message['content'],
                    },
                  )
                  .toList(),
              'user_text': userText,
              'project_snapshot': snapshot.toPromptSnapshot(),
              'selection_snapshot': snapshot.toSelectionSnapshot(),
              'project_id': snapshot.projectId,
              'ai_feature': _videoAiFeature,
              ...AnalyticsService.instance.buildRequestContext(),
            },
          ),
        )
        .timeout(requestTimeout);
  }

  Map<String, dynamic> _buildOpenAiBody({
    required String userText,
    required VideoEditorAiProjectSnapshot snapshot,
    required List<Map<String, String>> conversation,
  }) {
    return <String, dynamic>{
      'model': model,
      'temperature': 0.1,
      'instructions': _systemPrompt,
      'input': <Map<String, String>>[
        ...conversation.map(
          (message) => <String, String>{
            'role': message['role'] ?? 'user',
            'content': message['content'] ?? '',
          },
        ),
        <String, String>{
          'role': 'user',
          'content': 'PROJECT_SNAPSHOT:\n${snapshot.toPromptSnapshot()}',
        },
        <String, String>{
          'role': 'user',
          'content': 'SELECTION_SNAPSHOT:\n${snapshot.toSelectionSnapshot()}',
        },
        <String, String>{
          'role': 'user',
          'content': userText,
        },
      ],
      'tools': _tools,
      'tool_choice': 'required',
    };
  }

  VideoEditorAiResponse? _parseResponsePayload(dynamic payload) {
    final root = payload is Map<String, dynamic>
        ? payload
        : (payload is Map ? Map<String, dynamic>.from(payload) : null);
    if (root == null) return null;

    final outputs = (root['output'] as List?) ?? const <dynamic>[];
    String? assistantText;

    for (final output in outputs) {
      if (output is! Map) continue;
      final type = output['type']?.toString().trim();
      if (type == 'function_call') {
        final name = output['name']?.toString().trim();
        if ((name ?? '').isEmpty) continue;

        final rawArgs = output['arguments'];
        final args = rawArgs is Map<String, dynamic>
            ? rawArgs
            : (rawArgs is Map
                ? Map<String, dynamic>.from(rawArgs)
                : (rawArgs is String
                    ? Map<String, dynamic>.from(jsonDecode(rawArgs))
                    : <String, dynamic>{}));

        if (name == 'informational_response') {
          return VideoEditorAiResponse(
            message: (args['message'] as String?)?.trim() ??
                'I could not apply that edit.',
          );
        }

        if (name == 'video_editor_actions') {
          final rawActions = (args['actions'] as List?) ?? const <dynamic>[];
          final actions = rawActions
              .whereType<Map>()
              .map((raw) =>
                  VideoEditorAiAction.fromJson(Map<String, dynamic>.from(raw)))
              .where((action) => action.type.isNotEmpty)
              .toList(growable: false);
          final message = (args['assistant_message'] as String?)?.trim();
          return VideoEditorAiResponse(
            message: (message == null || message.isEmpty)
                ? 'Applied the requested timeline changes.'
                : message,
            actions: actions,
          );
        }
      }

      if (type == 'message') {
        final content = output['content'];
        if (content is! List) continue;
        for (final item in content) {
          if (item is! Map) continue;
          if (item['type'] != 'output_text') continue;
          final text = item['text'];
          if (text is String && text.trim().isNotEmpty) {
            assistantText ??= text.trim();
          }
        }
      }
    }

    if ((assistantText ?? '').isNotEmpty) {
      return VideoEditorAiResponse(message: assistantText!.trim());
    }
    return null;
  }

  static const String _systemPrompt = '''
You are Mixroom's video timeline assistant for a lightweight mobile editor.

You do not render files yourself. You only return structured actions the app can execute.
Think like a fast editor inside CapCut, iMovie, Premiere, or Vegas.

You have two tools:
1. informational_response
2. video_editor_actions

Use informational_response when:
- the user is asking what you can do
- the request is unsupported by the current editor
- the request is ambiguous enough that editing would be risky

Use video_editor_actions when the request clearly maps to timeline edits.

Supported action types:
- clip_edit
  - operations: split, trim, move, duplicate, delete, mute, unmute, set_volume
- transition_edit
  - operations: add, remove, set_duration, set_type
- playhead
  - set the playhead location with at_ms
- clarify
  - ask a short forced-choice question when absolutely necessary

Rules:
- Prefer direct execution over questions when the intent is clear.
- Use clip_id, track_id, and transition_id from the snapshot whenever possible.
- The PROJECT_SNAPSHOT and SELECTION_SNAPSHOT are authoritative.
- If there is a selected clip and the user does not name another clip, target the selected clip.
- Keep assistant_message short, practical, and in the same language as the user.
- Never invent unsupported features such as captions, masking, color grading, motion tracking, keyframes, cropping, AI generation, or true speed-ramping if the request requires them. Use informational_response instead.
- Never output plain JSON as chat text.
''';

  static const List<Map<String, dynamic>> _tools = <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'function',
      'name': 'informational_response',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'message': <String, dynamic>{
            'type': 'string',
          },
        },
        'required': <String>['message'],
      },
    },
    <String, dynamic>{
      'type': 'function',
      'name': 'video_editor_actions',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'assistant_message': <String, dynamic>{
            'type': 'string',
          },
          'actions': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'type': <String, dynamic>{
                  'type': 'string',
                  'enum': <String>[
                    'clip_edit',
                    'transition_edit',
                    'playhead',
                    'clarify',
                  ],
                },
                'data': <String, dynamic>{
                  'type': 'object',
                },
              },
              'required': <String>['type', 'data'],
            },
          },
        },
        'required': <String>['assistant_message', 'actions'],
      },
    },
  ];
}
