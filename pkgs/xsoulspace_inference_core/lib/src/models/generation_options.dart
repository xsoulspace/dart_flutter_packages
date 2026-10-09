import 'package:from_json_to_json/from_json_to_json.dart';

/// ADR 0059 — the typed generation knobs a request may carry, as one
/// const-constructible immutable value object: a consumer composes the
/// options once and attaches them anywhere (request construction,
/// `InferenceRequest.copyWith`), instead of threading four loose fields.
///
/// `thinking` is the request-level reasoning switch every provider can
/// mean: reasoning-native casts render it into their generation prompt
/// (Qwen `enable_thinking`), hosted providers map it to their reasoning
/// controls, and casts without a thinking switch answer with an honest
/// warning rather than silently ignoring it.
class GenerationOptions {
  const GenerationOptions({
    this.maxTokens,
    this.temperature,
    this.stopSequences = const <String>[],
    this.thinking,
  });

  factory GenerationOptions.fromJson(final Map<String, dynamic> json) =>
      GenerationOptions(
        maxTokens: switch (json['max_tokens']) {
          final int tokens => tokens,
          _ => null,
        },
        temperature: switch (json['temperature']) {
          final num temperature => temperature.toDouble(),
          _ => null,
        },
        stopSequences: jsonDecodeListAs<String>(json['stop_sequences']),
        thinking: switch (json['thinking']) {
          final bool thinking => thinking,
          _ => null,
        },
      );

  /// Upper bound on generated tokens. Providers with a required limit
  /// (Anthropic `max_tokens`) reject the request when this is absent
  /// instead of inventing a provider-specific default.
  final int? maxTokens;
  final double? temperature;
  final List<String> stopSequences;

  /// The request-level reasoning switch (see the class docs). Null =
  /// whatever the provider's own default is.
  final bool? thinking;

  GenerationOptions copyWith({
    final int? maxTokens,
    final double? temperature,
    final List<String>? stopSequences,
    final bool? thinking,
  }) => GenerationOptions(
    maxTokens: maxTokens ?? this.maxTokens,
    temperature: temperature ?? this.temperature,
    stopSequences: stopSequences ?? this.stopSequences,
    thinking: thinking ?? this.thinking,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'max_tokens': ?maxTokens,
    'temperature': ?temperature,
    if (stopSequences.isNotEmpty) 'stop_sequences': stopSequences,
    'thinking': ?thinking,
  };
}
