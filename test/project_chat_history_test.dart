import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_chat_history.dart';

void main() {
  const storedLimits = ProjectChatHistoryLimits(
    maxStoredMessages: 3,
    maxStoredCharacters: 20,
    maxStoredMessageCharacters: 8,
    maxConversationMessages: 2,
    maxConversationCharacters: 12,
  );
  const conversationLimits = ProjectChatHistoryLimits(
    maxStoredMessages: 10,
    maxStoredCharacters: 200,
    maxStoredMessageCharacters: 200,
    maxConversationMessages: 2,
    maxConversationCharacters: 60,
  );

  TextMessage buildMessage({
    required String id,
    required String authorId,
    required String text,
    int createdAtMs = 0,
    Map<String, dynamic>? metadata,
  }) {
    return TextMessage(
      id: id,
      authorId: authorId,
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
      metadata: metadata,
    );
  }

  test('stores newest persisted messages within configured limits', () {
    final history = ProjectChatHistory.fromChatMessages(
      [
        buildMessage(
            id: '1', authorId: 'assistant', text: 'alpha', createdAtMs: 1),
        buildMessage(id: '2', authorId: 'user', text: 'bravo', createdAtMs: 2),
        buildMessage(
            id: '3',
            authorId: 'assistant',
            text: 'charlie-very-long',
            createdAtMs: 3),
        buildMessage(
          id: '4',
          authorId: 'system',
          text: 'typing',
          createdAtMs: 4,
          metadata: {'typing': true},
        ),
        buildMessage(id: '5', authorId: 'user', text: 'delta', createdAtMs: 5),
      ],
      limits: storedLimits,
    );

    expect(history.truncated, isTrue);
    expect(history.messages.map((message) => message.id), ['2', '3', '5']);
    expect(history.messages[1].text, 'charlie…');
    expect(history.messages.last.text, 'delta');
  });

  test('conversation export keeps only user and assistant roles', () {
    final history = ProjectChatHistory.fromJson({
      'messages': [
        {
          'id': '1',
          'authorId': 'system',
          'text': 'Saved',
          'createdAtMs': 1,
        },
        {
          'id': '2',
          'authorId': 'user',
          'text': 'Need more punch',
          'createdAtMs': 2,
        },
        {
          'id': '3',
          'authorId': 'assistant',
          'text': 'I boosted the drums',
          'createdAtMs': 3,
        },
        {
          'id': '4',
          'authorId': 'user',
          'text': 'And tame the vocal harshness',
          'createdAtMs': 4,
        },
      ],
    }, limits: conversationLimits);

    expect(
      history.toConversation(limits: conversationLimits),
      [
        {
          'role': 'assistant',
          'content': 'I boosted the drums',
        },
        {
          'role': 'user',
          'content': 'And tame the vocal harshness',
        },
      ],
    );
  });

  test('persists and restores conversation state session id', () {
    final history = ProjectChatHistory.fromChatMessages(
      [
        buildMessage(id: '1', authorId: 'user', text: 'hello'),
      ],
      stateSessionId: 'state-session-1',
    );

    final json = history.toJsonValue();
    expect(json?['stateSessionId'], 'state-session-1');

    final restored = ProjectChatHistory.fromJson(json);
    expect(restored.stateSessionId, 'state-session-1');
    expect(restored.messages.single.text, 'hello');
  });

  test('legacy chat history without state session id still restores', () {
    final history = ProjectChatHistory.fromJson([
      {
        'id': '1',
        'authorId': 'user',
        'text': 'legacy',
        'createdAtMs': 1,
      },
    ]);

    expect(history.stateSessionId, isEmpty);
    expect(history.messages.single.text, 'legacy');
  });
}
