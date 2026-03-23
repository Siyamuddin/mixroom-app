import 'dart:convert';
import 'dart:typed_data';

class FeedbackTextSanitizer {
  const FeedbackTextSanitizer._();

  static const int maxChars = 1500;
  static final RegExp _controlChars =
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');
  static final RegExp _inlineWhitespace = RegExp(r'[ \t]+');
  static final RegExp _excessNewlines = RegExp(r'\n{3,}');

  static String sanitize(
    String raw, {
    int maxCharacters = maxChars,
    bool preserveNewlines = true,
  }) {
    final normalizedLineEndings = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final withoutControlChars =
        normalizedLineEndings.replaceAll(_controlChars, '');
    final lines = withoutControlChars
        .split('\n')
        .map((line) => line.replaceAll(_inlineWhitespace, ' ').trim())
        .toList(growable: false);
    final normalized = preserveNewlines
        ? lines.join('\n').replaceAll(_excessNewlines, '\n\n').trim()
        : lines.where((line) => line.isNotEmpty).join(' ').trim();
    if (normalized.length <= maxCharacters) {
      return normalized;
    }
    return normalized.substring(0, maxCharacters).trimRight();
  }
}

enum FeedbackCategory {
  feedback,
  bugReport,
}

extension FeedbackCategoryApi on FeedbackCategory {
  String get apiValue => switch (this) {
        FeedbackCategory.feedback => 'feedback',
        FeedbackCategory.bugReport => 'bug_report',
      };

  String get label => switch (this) {
        FeedbackCategory.feedback => 'Feedback',
        FeedbackCategory.bugReport => 'Bug report',
      };
}

enum FeedbackSource {
  home,
  account,
  dawChat,
}

extension FeedbackSourceApi on FeedbackSource {
  String get apiValue => switch (this) {
        FeedbackSource.home => 'home',
        FeedbackSource.account => 'account',
        FeedbackSource.dawChat => 'daw_chat',
      };
}

class FeedbackDraft {
  const FeedbackDraft({
    required this.category,
    required this.message,
    this.allowEmailContact = false,
    this.includeDawContext = false,
    this.includeDawScreenshot = false,
  });

  final FeedbackCategory category;
  final String message;
  final bool allowEmailContact;
  final bool includeDawContext;
  final bool includeDawScreenshot;
}

class FeedbackContextPayload {
  const FeedbackContextPayload({
    this.chatHistory,
    this.projectSettings,
  });

  final List<Map<String, String>>? chatHistory;
  final Map<String, dynamic>? projectSettings;

  Map<String, dynamic>? toJson() {
    final payload = <String, dynamic>{};
    if (chatHistory != null && chatHistory!.isNotEmpty) {
      payload['chat_history'] = chatHistory;
    }
    if (projectSettings != null && projectSettings!.isNotEmpty) {
      payload['project_settings'] = projectSettings;
    }
    return payload.isEmpty ? null : payload;
  }
}

class FeedbackScreenshotAttachment {
  const FeedbackScreenshotAttachment({
    required this.bytes,
    required this.mimeType,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    };
  }
}

class FeedbackSubmissionRequest {
  const FeedbackSubmissionRequest({
    required this.category,
    required this.source,
    required this.message,
    this.allowEmailContact = false,
    this.context,
    this.screenshot,
  });

  final FeedbackCategory category;
  final FeedbackSource source;
  final String message;
  final bool allowEmailContact;
  final FeedbackContextPayload? context;
  final FeedbackScreenshotAttachment? screenshot;

  Map<String, dynamic> toJson({
    required Map<String, String> client,
  }) {
    return <String, dynamic>{
      'category': category.apiValue,
      'source': source.apiValue,
      'message': FeedbackTextSanitizer.sanitize(message),
      'allow_email_contact': allowEmailContact,
      if (client.isNotEmpty) 'client': client,
      if (context?.toJson() != null) 'context': context!.toJson(),
      if (screenshot != null) 'screenshot': screenshot!.toJson(),
    };
  }
}
