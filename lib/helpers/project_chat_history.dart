import 'package:flutter_chat_core/flutter_chat_core.dart';

const ProjectChatHistoryLimits kDefaultProjectChatHistoryLimits =
    ProjectChatHistoryLimits(
  maxStoredMessages: 48,
  maxStoredCharacters: 16000,
  maxStoredMessageCharacters: 2000,
  maxConversationMessages: 24,
  maxConversationCharacters: 12000,
);

class ProjectChatHistoryLimits {
  final int maxStoredMessages;
  final int maxStoredCharacters;
  final int maxStoredMessageCharacters;
  final int maxConversationMessages;
  final int maxConversationCharacters;

  const ProjectChatHistoryLimits({
    required this.maxStoredMessages,
    required this.maxStoredCharacters,
    required this.maxStoredMessageCharacters,
    required this.maxConversationMessages,
    required this.maxConversationCharacters,
  });
}

class ProjectChatHistoryEntry {
  final String id;
  final String authorId;
  final String text;
  final DateTime createdAt;

  const ProjectChatHistoryEntry({
    required this.id,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  ProjectChatHistoryEntry copyWith({
    String? id,
    String? authorId,
    String? text,
    DateTime? createdAt,
  }) {
    return ProjectChatHistoryEntry(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String? normalizeAuthorId(String? rawAuthorId) {
    final normalized = (rawAuthorId ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'user':
      case 'assistant':
      case 'system':
        return normalized;
      default:
        return null;
    }
  }

  static ProjectChatHistoryEntry? fromJson(
    Object? raw, {
    required int fallbackIndex,
  }) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final authorId = normalizeAuthorId(json['authorId'] as String?);
    final text = (json['text'] as String? ?? '').trim();
    if (authorId == null || text.isEmpty) return null;

    final createdAt =
        _parseDateTime(json['createdAtMs'] ?? json['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(
              fallbackIndex,
              isUtc: true,
            );
    final fallbackId =
        'project_chat_${createdAt.millisecondsSinceEpoch}_$fallbackIndex';
    final id = (json['id'] as String?)?.trim();

    return ProjectChatHistoryEntry(
      id: (id == null || id.isEmpty) ? fallbackId : id,
      authorId: authorId,
      text: text,
      createdAt: createdAt,
    );
  }

  static ProjectChatHistoryEntry? fromMessage(Message message) {
    if (message is! TextMessage) return null;
    final authorId = normalizeAuthorId(message.authorId);
    final text = message.text.trim();
    if (authorId == null || text.isEmpty) return null;

    final metadata = message.metadata;
    if (metadata != null && metadata['typing'] == true) {
      return null;
    }

    return ProjectChatHistoryEntry(
      id: message.id,
      authorId: authorId,
      text: text,
      createdAt: message.createdAt?.toUtc() ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'text': text,
      'createdAtMs': createdAt.toUtc().millisecondsSinceEpoch,
    };
  }

  TextMessage toTextMessage() {
    return TextMessage(
      id: id,
      authorId: authorId,
      createdAt: createdAt.toUtc(),
      text: text,
    );
  }

  Map<String, String>? toConversationEntry() {
    if (authorId != 'user' && authorId != 'assistant') return null;
    return {
      'role': authorId,
      'content': text,
    };
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim())?.toUtc();
    }
    return null;
  }
}

class ProjectChatHistory {
  final List<ProjectChatHistoryEntry> messages;
  final bool truncated;

  const ProjectChatHistory({
    this.messages = const <ProjectChatHistoryEntry>[],
    this.truncated = false,
  });

  factory ProjectChatHistory.fromJson(
    Object? raw, {
    ProjectChatHistoryLimits limits = kDefaultProjectChatHistoryLimits,
  }) {
    final parsed = <ProjectChatHistoryEntry>[];
    bool truncated = false;

    if (raw is Map) {
      final json = raw.cast<String, dynamic>();
      truncated = json['truncated'] == true;
      final rawMessages = json['messages'];
      if (rawMessages is List) {
        for (int i = 0; i < rawMessages.length; i++) {
          final entry = ProjectChatHistoryEntry.fromJson(rawMessages[i],
              fallbackIndex: i);
          if (entry != null) parsed.add(entry);
        }
      }
    } else if (raw is List) {
      for (int i = 0; i < raw.length; i++) {
        final entry =
            ProjectChatHistoryEntry.fromJson(raw[i], fallbackIndex: i);
        if (entry != null) parsed.add(entry);
      }
    }

    return _normalize(
      parsed,
      limits: limits,
      preserveTruncated: truncated,
      maxMessages: limits.maxStoredMessages,
      maxCharacters: limits.maxStoredCharacters,
    );
  }

  factory ProjectChatHistory.fromChatMessages(
    Iterable<Message> source, {
    ProjectChatHistoryLimits limits = kDefaultProjectChatHistoryLimits,
  }) {
    final parsed = <ProjectChatHistoryEntry>[];
    for (final message in source) {
      final entry = ProjectChatHistoryEntry.fromMessage(message);
      if (entry != null) parsed.add(entry);
    }

    return _normalize(
      parsed,
      limits: limits,
      preserveTruncated: false,
      maxMessages: limits.maxStoredMessages,
      maxCharacters: limits.maxStoredCharacters,
    );
  }

  List<TextMessage> toChatMessages() {
    return messages
        .map((entry) => entry.toTextMessage())
        .toList(growable: false);
  }

  List<Map<String, String>> toConversation({
    ProjectChatHistoryLimits limits = kDefaultProjectChatHistoryLimits,
  }) {
    final entries = messages
        .map((entry) => entry.toConversationEntry())
        .whereType<Map<String, String>>()
        .toList(growable: false);
    if (entries.isEmpty) return const <Map<String, String>>[];

    final limited = <Map<String, String>>[];
    int totalCharacters = 0;
    final afterCountLimit = entries.length > limits.maxConversationMessages
        ? entries.sublist(entries.length - limits.maxConversationMessages)
        : entries;

    for (final entry in afterCountLimit.reversed) {
      final content = entry['content'] ?? '';
      final remaining = limits.maxConversationCharacters - totalCharacters;
      if (remaining <= 0) break;
      if (content.length > remaining) {
        if (limited.isEmpty) {
          limited.add({
            'role': entry['role'] ?? 'user',
            'content': _truncateText(content, remaining),
          });
        }
        break;
      }
      limited.add(entry);
      totalCharacters += content.length;
    }

    return limited.reversed.toList(growable: false);
  }

  Map<String, dynamic>? toJsonValue() {
    if (messages.isEmpty) return null;
    return {
      'messages': messages.map((entry) => entry.toJson()).toList(),
      if (truncated) 'truncated': true,
    };
  }

  static ProjectChatHistory _normalize(
    List<ProjectChatHistoryEntry> source, {
    required ProjectChatHistoryLimits limits,
    required bool preserveTruncated,
    required int maxMessages,
    required int maxCharacters,
  }) {
    bool truncated = preserveTruncated;
    final normalized = <ProjectChatHistoryEntry>[];

    for (final entry in source) {
      final trimmedText =
          _truncateText(entry.text, limits.maxStoredMessageCharacters);
      if (trimmedText != entry.text) truncated = true;
      normalized.add(entry.copyWith(text: trimmedText));
    }

    final afterCountLimit = normalized.length > maxMessages
        ? normalized.sublist(normalized.length - maxMessages)
        : normalized;
    if (afterCountLimit.length != normalized.length) truncated = true;

    final limited = <ProjectChatHistoryEntry>[];
    int totalCharacters = 0;

    for (final entry in afterCountLimit.reversed) {
      final remaining = maxCharacters - totalCharacters;
      if (remaining <= 0) {
        truncated = true;
        continue;
      }

      if (entry.text.length > remaining) {
        if (limited.isEmpty) {
          limited
              .add(entry.copyWith(text: _truncateText(entry.text, remaining)));
        }
        truncated = true;
        continue;
      }

      limited.add(entry);
      totalCharacters += entry.text.length;
    }

    return ProjectChatHistory(
      messages: limited.reversed.toList(growable: false),
      truncated: truncated,
    );
  }

  static String _truncateText(String text, int maxCharacters) {
    if (maxCharacters <= 0) return '';
    if (text.length <= maxCharacters) return text;
    if (maxCharacters == 1) return text.substring(0, 1);
    return '${text.substring(0, maxCharacters - 1)}…';
  }
}
