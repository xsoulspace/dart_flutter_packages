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

  static ChatRole? fromJson(final Object? value) => switch (value) {
    'system' => ChatRole.system,
    'user' => ChatRole.user,
    'assistant' => ChatRole.assistant,
    'tool' => ChatRole.tool,
    _ => null,
  };

  String toJson() => name;
}

final class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  const ChatMessage.system(final String content)
    : this(role: ChatRole.system, content: content);
  const ChatMessage.user(final String content)
    : this(role: ChatRole.user, content: content);
  const ChatMessage.assistant(final String content)
    : this(role: ChatRole.assistant, content: content);
  const ChatMessage.tool(final String content)
    : this(role: ChatRole.tool, content: content);

  factory ChatMessage.fromJson(final Map<String, dynamic> json) {
    final content = jsonDecodeString(json['content']);
    final role = ChatRole.fromJson(json['role']) ?? ChatRole.user;
    return ChatMessage(role: role, content: content);
  }

  final ChatRole role;
  final String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role.toJson(),
    'content': content,
  };
}
