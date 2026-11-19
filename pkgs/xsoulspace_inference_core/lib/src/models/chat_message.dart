import 'package:from_json_to_json/from_json_to_json.dart';

/// ADR 0059 — the minimal conversation value object. Chat-native
/// providers render a `messages` list directly (native engines through
/// their fixture-gated chat templates); prompt-composing providers keep
/// folding `prompt`/`systemPrompt`/`contextFragments` as before. JSON
/// round-trips for wire transports.
enum ChatRole {
  system,
  user,
  assistant,
  tool;

  static ChatRole? fromJson(Object? value) => switch (value) {
    'system' => ChatRole.system,
    'user' => ChatRole.user,
    'assistant' => ChatRole.assistant,
    'tool' => ChatRole.tool,
    _ => null,
  };

  String toJson() => name;
}

final class ChatMessage {
  const ChatMessage({required ChatRole role, required String content})
    : this._(role: role, content: content);

  const ChatMessage.system(String content)
    : this(role: ChatRole.system, content: content);
  const ChatMessage.user(String content)
    : this(role: ChatRole.user, content: content);
  const ChatMessage.assistant(String content)
    : this(role: ChatRole.assistant, content: content);
  const ChatMessage.tool(String content)
    : this(role: ChatRole.tool, content: content);

  const ChatMessage._({
    required this.role,
    required this.content,
    this.parts,
  });

  /// MULTIPART (native-image-assets wave C): a user turn whose content
  /// is TYPED PARTS (text + image) — the vision lane. `content` carries
  /// the TEXT parts joined (the string projection every text-only
  /// consumer reads); [parts] carries the typed truth the wire renders
  /// as a content array. Null parts = the plain string shape
  /// (byte-identical JSON — the pre-existing contract).
  factory ChatMessage.userParts(List<ChatMessagePart> parts) {
    final text = [
      for (final part in parts)
        if (part.text != null) part.text!,
    ].join('\n');
    return ChatMessage._(role: ChatRole.user, content: text, parts: parts);
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = ChatRole.fromJson(json['role']) ?? ChatRole.user;
    return switch (json['content']) {
      final List raw => () {
        final parts = [
          for (final entry in raw)
            if (entry is Map<String, dynamic>) ChatMessagePart.fromJson(entry),
        ];
        return ChatMessage._(
          role: role,
          content: parts.textProjection,
          parts: parts,
        );
      }(),
      _ => ChatMessage(
        role: role,
        content: jsonDecodeString(json['content']),
      ),
    };
  }

  final ChatRole role;
  final String content;

  /// Typed content parts when this message is multipart (vision);
  /// null keeps the wire `content` a String.
  final List<ChatMessagePart>? parts;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role.toJson(),
    'content': parts == null
        ? content
        : [for (final part in parts!) part.toJson()],
  };
}

extension on List<ChatMessagePart> {
  String get textProjection => [
    for (final part in this)
      if (part.text != null) part.text!,
  ].join('\n');
}

/// One typed content part of a multipart [ChatMessage]: text or image.
/// The image carrier is a DATA URL (`data:<mime>;base64,<...>`) — the
/// OpenAI-vision shape every chat-completions-compatible vision model
/// serves. The diagnostics size law applies at the OBSERVATIONAL
/// boundaries (transport diagnostics, logs): data URLs become
/// `[[data-url:N chars]]` markers there, never in the wire body.
final class ChatMessagePart {
  const ChatMessagePart._({this.text, this.imageDataUrl});

  factory ChatMessagePart.text(String value) =>
      ChatMessagePart._(text: value);

  factory ChatMessagePart.imageDataUrl(String url) =>
      ChatMessagePart._(imageDataUrl: url);

  factory ChatMessagePart.fromJson(Map<String, dynamic> json) {
    final text = jsonDecodeString(json['text']);
    if (text.trim().isNotEmpty) return ChatMessagePart.text(text);
    final url = switch (json['image_url']) {
      final Map image => jsonDecodeString(image['url'].toString()),
      _ => '',
    };
    return ChatMessagePart.imageDataUrl(url);
  }

  /// The part's text; null on an image part.
  final String? text;

  /// The part's data URL; null on a text part.
  final String? imageDataUrl;

  bool get isImage => imageDataUrl != null;

  Map<String, dynamic> toJson() => isImage
      ? {
          'type': 'image_url',
          'image_url': {'url': imageDataUrl},
        }
      : {'type': 'text', 'text': text};
}
