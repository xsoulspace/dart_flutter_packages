import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:recase/recase.dart';

import '../structured_output/structured_output.dart';
import '../tools/tool_contracts.dart';
import 'chat_message.dart';
import 'generation_options.dart';

export 'chat_message.dart';
export 'generation_options.dart';
export 'model_catalog.dart';

/// The idea is that inference task should be as atomic as possible
/// so if structural output is needed it should be pointed as such
/// or relevant config for API passed.
enum InferenceTask {
  text,

  /// fallback for [nativelyStructuredText]
  implicitlyStructuredText,

  /// should be primary target for all platforms
  nativelyStructuredText,
  speechToText,
  textToSpeech;

  factory InferenceTask.fromJson(Object? value) {
    if (value is! String) {
      return InferenceTask.implicitlyStructuredText;
    }

    try {
      return InferenceTask.values.byName(value);
      // ignore: avoid_catches_without_on_clauses, empty_catches
    } catch (e) {}

    return InferenceTask.implicitlyStructuredText;
  }
}

enum InferenceAudioSource {
  filePath,
  bytes,
  microphone;

  static String toJson(InferenceAudioSource source) =>
      source.name.snakeCase;

  static InferenceAudioSource? fromJson(Object? value) {
    if (value is! String) {
      return null;
    }

    return switch (value) {
      'file_path' || 'filePath' => InferenceAudioSource.filePath,
      'bytes' => InferenceAudioSource.bytes,
      'microphone' => InferenceAudioSource.microphone,
      _ => null,
    };
  }
}

/// in apple, [contextFragments] will become Transcript.prompt
// TODO(arenukvern): make it more native i.e. apple -> transcript
/// i.e. embrace different views - completion api for openai, apple transcript
/// etc...
/// or just text
extension type const InferenceRequest._(Map<String, dynamic> value) {
  factory InferenceRequest({
    required String prompt,
    Map<String, dynamic> outputSchema = const {},
    String workingDirectory = '',
    String systemPrompt = '',
    List<Object> contextFragments = const [],
    Map<String, dynamic> metadata = const <String, dynamic>{},
    InferenceTask task = InferenceTask.text,
    InferenceAudioInput? audioInput,
    InferenceVoiceOptions? voiceOptions,
    List<ChatMessage> messages = const [],

    /// The full conversation (ADR 0059). Chat-native providers render it
    /// directly; empty = synthesize from [systemPrompt] + [prompt] as
    /// before.
    int? maxTokens,
    double? temperature,
    List<String> stopSequences = const [],

    /// Request-level reasoning switch (ADR 0059). Null = the provider's
    /// own default.
    bool? thinking,
    String? reasoningEffort,

    /// Whether the provider should return its reasoning trace (ADR 0059 —
    /// alongside the thinking switch and the explicit effort).
    bool? includeReasoning,
  }) => InferenceRequest._(
    _buildRequestMap(
      prompt: prompt,
      outputSchema: outputSchema,
      workingDirectory: workingDirectory,
      systemPrompt: systemPrompt,
      contextFragments: contextFragments,
      metadata: metadata,
      task: task,
      audioInput: audioInput,
      voiceOptions: voiceOptions,
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
      stopSequences: stopSequences,
      thinking: thinking,
      reasoningEffort: reasoningEffort,
      includeReasoning: includeReasoning,
    ),
  );
  factory InferenceRequest.structured({
    required String prompt,
    SchemaBundle outputSchema = SchemaBundle.empty,
    String workingDirectory = '',
    String systemPrompt = '',
    List<Object> contextFragments = const [],
    Map<String, dynamic> metadata = const <String, dynamic>{},
    InferenceTask task = InferenceTask.text,
    InferenceAudioInput? audioInput,
    InferenceVoiceOptions? voiceOptions,
    List<ChatMessage> messages = const [],
    int? maxTokens,
    double? temperature,
    List<String> stopSequences = const [],
    bool? thinking,
    String? reasoningEffort,
    bool? includeReasoning,
  }) => InferenceRequest._(
    _buildRequestMap(
      prompt: prompt,
      outputSchema: outputSchema.toJson(),
      workingDirectory: workingDirectory,
      systemPrompt: systemPrompt,
      contextFragments: contextFragments,
      metadata: metadata,
      task: task,
      audioInput: audioInput,
      voiceOptions: voiceOptions,
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
      stopSequences: stopSequences,
      thinking: thinking,
      reasoningEffort: reasoningEffort,
      includeReasoning: includeReasoning,
    ),
  );

  factory InferenceRequest.fromJson(Map<String, dynamic> json) =>
      InferenceRequest._(json);

  factory InferenceRequest.speechToText({
    required InferenceAudioInput audioInput,
    List<Object> contextFragments = const [],
    String systemPrompt = '',
    String workingDirectory = '.',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => InferenceRequest(
    prompt: '',
    contextFragments: contextFragments,
    systemPrompt: systemPrompt,
    workingDirectory: workingDirectory,
    metadata: metadata,
    task: InferenceTask.speechToText,
    audioInput: audioInput,
  );

  factory InferenceRequest.textToSpeech({
    required String text,
    String workingDirectory = '.',
    String systemPrompt = '',
    InferenceVoiceOptions? voiceOptions,
    Map<String, dynamic> metadata = const <String, dynamic>{},
    List<Object> contextFragments = const [],
  }) => InferenceRequest(
    prompt: text,
    contextFragments: contextFragments,
    systemPrompt: systemPrompt,
    workingDirectory: workingDirectory,
    metadata: metadata,
    task: InferenceTask.textToSpeech,
    voiceOptions: voiceOptions,
  );

  /// The one request-map builder behind both public factories (ADR 0059
  /// dedupe — the field list existed twice and drifted once already).
  static Map<String, dynamic> _buildRequestMap({
    required String prompt,
    required Map<String, dynamic> outputSchema,
    required String workingDirectory,
    required String systemPrompt,
    required List<Object> contextFragments,
    required Map<String, dynamic> metadata,
    required InferenceTask task,
    required InferenceAudioInput? audioInput,
    required InferenceVoiceOptions? voiceOptions,
    required List<ChatMessage> messages,
    required int? maxTokens,
    required double? temperature,
    required List<String> stopSequences,
    required bool? thinking,
    required String? reasoningEffort,
    required bool? includeReasoning,
  }) => <String, dynamic>{
    'task': task.name,
    'prompt': prompt,
    'output_schema': outputSchema,
    'working_directory': workingDirectory,
    'system_prompt': systemPrompt,
    'context_fragments': contextFragments,
    'metadata': metadata,
    'audio_input': ?audioInput?.toJson(),
    'voice_options': ?voiceOptions?.toJson(),
    if (messages.isNotEmpty)
      'messages': <Map<String, dynamic>>[
        for (final message in messages) message.toJson(),
      ],
    'max_tokens': ?maxTokens,
    'temperature': ?temperature,
    if (stopSequences.isNotEmpty) 'stop_sequences': stopSequences,
    'thinking': ?thinking,
    'reasoning_effort': ?reasoningEffort,
    'include_reasoning': ?includeReasoning,
  };

  String get prompt => jsonDecodeString(value['prompt']);
  Map<String, dynamic> get outputSchema =>
      jsonDecodeMapAs(value['output_schema']);
  SchemaBundle get outputSchemaBundle => SchemaBundle.fromJson(outputSchema);
  String get workingDirectory => jsonDecodeString(value['working_directory']);
  Map<String, dynamic> get metadata => jsonDecodeMapAs(value['metadata']);
  InferenceTask get task => InferenceTask.fromJson(value['task']);
  InferenceAudioInput? get audioInput => switch (value['audio_input']) {
    final Map value => InferenceAudioInput.fromJson(
      value.cast<String, dynamic>(),
    ),
    _ => null,
  };
  InferenceVoiceOptions? get voiceOptions => switch (value['voice_options']) {
    final Map value => InferenceVoiceOptions.fromJson(
      value.cast<String, dynamic>(),
    ),
    _ => null,
  };
  List<Object> get contextFragments =>
      jsonDecodeListAs<Object>(value['context_fragments']);
  String get contextFragmentsJson =>
      contextFragments.isNotEmpty ? jsonEncode(contextFragments) : '';
  String get systemPrompt => jsonDecodeString(value['system_prompt']);
  int? get maxTokens => switch (value['max_tokens']) {
    final int tokens => tokens,
    _ => null,
  };
  double? get temperature => switch (value['temperature']) {
    final num temperature => temperature.toDouble(),
    _ => null,
  };
  List<String> get stopSequences =>
      jsonDecodeListAs<String>(value['stop_sequences']);
  bool? get thinking => switch (value['thinking']) {
    final bool thinking => thinking,
    _ => null,
  };
  String? get reasoningEffort => switch (value['reasoning_effort']) {
    final String effort => effort,
    _ => null,
  };
  bool? get includeReasoning => switch (value['include_reasoning']) {
    final bool include => include,
    _ => null,
  };
  List<ChatMessage> get messages => <ChatMessage>[
    for (final json in jsonDecodeListAs<Map<String, dynamic>>(
      value['messages'],
    ))
      ChatMessage.fromJson(json),
  ];

  /// The flat generation fields viewed as one composable value (ADR 0059
  /// — single storage: this map; the view never diverges from it).
  GenerationOptions get generationOptions => GenerationOptions(
    maxTokens: maxTokens,
    temperature: temperature,
    stopSequences: stopSequences,
    thinking: thinking,
    reasoningEffort: reasoningEffort,
    includeReasoning: includeReasoning,
  );

  /// Derives a request with the given fields replaced (ADR 0059 — set-if-
  /// provided, like [GenerationOptions.copyWith]; nothing clears to null).
  InferenceRequest copyWith({
    String? prompt,
    Map<String, dynamic>? outputSchema,
    String? workingDirectory,
    String? systemPrompt,
    List<Object>? contextFragments,
    Map<String, dynamic>? metadata,
    InferenceTask? task,
    InferenceAudioInput? audioInput,
    InferenceVoiceOptions? voiceOptions,
    List<ChatMessage>? messages,
    int? maxTokens,
    double? temperature,
    List<String>? stopSequences,
    bool? thinking,
    String? reasoningEffort,
    bool? includeReasoning,
  }) => InferenceRequest._(
    _buildRequestMap(
      prompt: prompt ?? this.prompt,
      outputSchema: outputSchema ?? this.outputSchema,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      contextFragments: contextFragments ?? this.contextFragments,
      metadata: metadata ?? this.metadata,
      task: task ?? this.task,
      audioInput: audioInput ?? this.audioInput,
      voiceOptions: voiceOptions ?? this.voiceOptions,
      messages: messages ?? this.messages,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      stopSequences: stopSequences ?? this.stopSequences,
      thinking: thinking ?? this.thinking,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      includeReasoning: includeReasoning ?? this.includeReasoning,
    ),
  );
}

class InferenceResponse {
  const InferenceResponse({
    this.structuredOutput = const {},
    this.rawOutput,
    this.presentationText,
    this.warnings = const <String>[],
    this.meta = const <String, dynamic>{},
    this.task = InferenceTask.implicitlyStructuredText,
    this.transcript,
    this.normalizedTranscript,
    this.segments = const <InferenceSpeechSegment>[],
    this.audioArtifact,
    this.toolResults = const [],
    this.toolCalls = const [],
  });

  factory InferenceResponse.fromJson(Map<String, dynamic> json) =>
      InferenceResponse(
        structuredOutput: jsonDecodeMap(json['output']),
        rawOutput: jsonDecodeString(json['raw_output']),
        presentationText: json['presentation_text'] as String?,
        warnings: jsonDecodeListAs(json['warnings']),
        meta: jsonDecodeMap(json['meta']),
        toolCalls: jsonDecodeListAs<Map<String, dynamic>>(
          json['tool_calls'],
        ).map(ToolCall.fromJson).toList(),
        toolResults: jsonDecodeListAs<Map<String, dynamic>>(
          json['tool_results'],
        ).map(ToolExecutionResult.fromJson).toList(),
        task: InferenceTask.fromJson(json['task']),
        transcript: jsonDecodeString(json['transcript']),
        normalizedTranscript: jsonDecodeString(json['normalized_transcript']),
        segments: jsonDecodeListAs<Map<String, dynamic>>(
          json['segments'],
        ).map(InferenceSpeechSegment.fromJson).toList(),
        audioArtifact: switch (json['audio_artifact']) {
          final Map value => InferenceAudioArtifact.fromJson(
            value.cast<String, dynamic>(),
          ),
          _ => null,
        },
      );

  final Map<String, dynamic> structuredOutput;
  final String? rawOutput;

  /// Provider-decoded discussion text. Empty means no discussion; null retains
  /// legacy raw presentation. Original evidence remains in [rawOutput].
  final String? presentationText;
  final List<String> warnings;
  final Map<String, dynamic> meta;
  final InferenceTask task;
  final String? transcript;
  final String? normalizedTranscript;
  final List<InferenceSpeechSegment> segments;
  final InferenceAudioArtifact? audioArtifact;
  final List<ToolExecutionResult> toolResults;

  /// Structured tool calls parsed by the inference client.
  ///
  /// Backends with native tool calling (OpenRouter, OpenAI, Apple Foundation)
  /// return parsed calls here directly — no tag round-trip. Raw/legacy backends
  /// that emit `<call|...>` tags in [rawOutput] leave this empty; the harness
  /// falls back to tag parsing for those.
  final List<ToolCall> toolCalls;

  Map<String, dynamic> toJson() => {
    'task': task.name,
    'output': structuredOutput,
    if (rawOutput != null) 'raw_output': rawOutput,
    if (presentationText != null) 'presentation_text': presentationText,
    if (transcript != null) 'transcript': transcript,
    if (normalizedTranscript != null)
      'normalized_transcript': normalizedTranscript,
    if (segments.isNotEmpty)
      'segments': segments.map((segment) => segment.toJson()).toList(),
    if (audioArtifact != null) 'audio_artifact': audioArtifact!.toJson(),
    'tool_results': toolResults.map((e) => e.toJson()).toList(),
    if (toolCalls.isNotEmpty)
      'tool_calls': toolCalls.map((e) => e.toJson()).toList(),
    'warnings': warnings,
    'meta': meta,
  };
}

class InferenceAudioInput {
  const InferenceAudioInput({
    required this.mimeType,
    this.source,
    this.filePath,
    this.bytes,
    this.sampleRateHz,
    this.channelCount,
  });

  factory InferenceAudioInput.fromJson(Map<String, dynamic> json) =>
      InferenceAudioInput(
        source: InferenceAudioSource.fromJson(json['source']),
        filePath: jsonDecodeString(json['file_path']),
        bytes: switch (json['bytes_base64']) {
          final String value => base64Decode(value),
          _ => null,
        },
        mimeType: jsonDecodeString(json['mime_type']),
        sampleRateHz: jsonDecodeInt(json['sample_rate_hz']),
        channelCount: jsonDecodeInt(json['channel_count']),
      );

  const InferenceAudioInput.filePath({
    required this.filePath,
    required this.mimeType,
    this.sampleRateHz,
    this.channelCount,
  }) : source = InferenceAudioSource.filePath,
       bytes = null;

  const InferenceAudioInput.bytes({
    required this.bytes,
    required this.mimeType,
    this.sampleRateHz,
    this.channelCount,
  }) : source = InferenceAudioSource.bytes,
       filePath = null;

  const InferenceAudioInput.microphone({
    this.mimeType = 'audio/webm',
    this.sampleRateHz,
    this.channelCount,
  }) : source = InferenceAudioSource.microphone,
       filePath = null,
       bytes = null;

  final InferenceAudioSource? source;
  final String? filePath;
  final List<int>? bytes;
  final String mimeType;
  final int? sampleRateHz;
  final int? channelCount;

  InferenceAudioSource? get resolvedSource {
    if (source != null) {
      return source;
    }

    final hasFilePath = (filePath ?? '').trim().isNotEmpty;
    final hasBytes = (bytes ?? const <int>[]).isNotEmpty;

    if (hasFilePath == hasBytes) {
      return null;
    }

    return hasFilePath
        ? InferenceAudioSource.filePath
        : InferenceAudioSource.bytes;
  }

  Map<String, dynamic> toJson() => {
    if (resolvedSource != null)
      'source': InferenceAudioSource.toJson(resolvedSource!),
    if (filePath != null) 'file_path': filePath,
    if (bytes != null) 'bytes_base64': base64Encode(bytes!),
    'mime_type': mimeType,
    if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
    if (channelCount != null) 'channel_count': channelCount,
  };
}

class InferenceAudioArtifact {
  const InferenceAudioArtifact({
    required this.filePath,
    required this.mimeType,
    this.durationMs,
  });

  factory InferenceAudioArtifact.fromJson(Map<String, dynamic> json) =>
      InferenceAudioArtifact(
        filePath: jsonDecodeString(json['file_path']),
        mimeType: jsonDecodeString(json['mime_type']),
        durationMs: jsonDecodeInt(json['duration_ms']),
      );

  final String filePath;
  final String mimeType;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
    'file_path': filePath,
    'mime_type': mimeType,
    if (durationMs != null) 'duration_ms': durationMs,
  };
}

class InferenceSpeechSegment {
  const InferenceSpeechSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  factory InferenceSpeechSegment.fromJson(Map<String, dynamic> json) =>
      InferenceSpeechSegment(
        text: jsonDecodeString(json['text']),
        startMs: jsonDecodeInt(json['start_ms']),
        endMs: jsonDecodeInt(json['end_ms']),
      );

  final String text;
  final int startMs;
  final int endMs;

  Map<String, dynamic> toJson() => {
    'text': text,
    'start_ms': startMs,
    'end_ms': endMs,
  };
}

class InferenceVoiceOptions {
  const InferenceVoiceOptions({
    this.voiceId,
    this.locale,
    this.speechRate,
    this.pitch,
    this.providerExtras = const <String, dynamic>{},
  });

  factory InferenceVoiceOptions.fromJson(Map<String, dynamic> json) =>
      InferenceVoiceOptions(
        voiceId: jsonDecodeString(json['voice_id']),
        locale: jsonDecodeString(json['locale']),
        speechRate: jsonDecodeDouble(json['speech_rate']),
        pitch: jsonDecodeDouble(json['pitch']),
        providerExtras: jsonDecodeMap(json['provider_extras']),
      );

  final String? voiceId;
  final String? locale;
  final double? speechRate;
  final double? pitch;
  final Map<String, dynamic> providerExtras;

  Map<String, dynamic> toJson() => {
    if (voiceId != null) 'voice_id': voiceId,
    if (locale != null) 'locale': locale,
    if (speechRate != null) 'speech_rate': speechRate,
    if (pitch != null) 'pitch': pitch,
    'provider_extras': providerExtras,
  };
}
