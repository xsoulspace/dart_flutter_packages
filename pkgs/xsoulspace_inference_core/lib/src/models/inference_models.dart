import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:recase/recase.dart';

import '../agent/structured_output/structured_output.dart';

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

  factory InferenceTask.fromJson(final Object? value) {
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

  static String toJson(final InferenceAudioSource source) =>
      source.name.snakeCase;

  static InferenceAudioSource? fromJson(final Object? value) {
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
/// TODO(arenukvern): make it more native for convertion fragments -> transcript
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
  }) => InferenceRequest._({
    'task': task.name,
    'prompt': prompt,
    'output_schema': outputSchema,
    'working_directory': workingDirectory,
    'system_prompt': systemPrompt,
    'context_fragments': contextFragments,
    'metadata': metadata,
    'audio_input': ?audioInput?.toJson(),
    'voice_options': ?voiceOptions?.toJson(),
  });
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
  }) => InferenceRequest._({
    'task': task.name,
    'prompt': prompt,
    'output_schema': outputSchema.toJson(),
    'working_directory': workingDirectory,
    'system_prompt': systemPrompt,
    'context_fragments': contextFragments,
    'metadata': metadata,
    'audio_input': ?audioInput?.toJson(),
    'voice_options': ?voiceOptions?.toJson(),
  });
  factory InferenceRequest.fromJson(final Map<String, dynamic> json) =>
      InferenceRequest._(json);

  factory InferenceRequest.speechToText({
    required final InferenceAudioInput audioInput,
    final List<Object> contextFragments = const [],
    final String systemPrompt = '',
    final String workingDirectory = '.',
    final Map<String, dynamic> metadata = const <String, dynamic>{},
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
    required final String text,
    final String workingDirectory = '.',
    final String systemPrompt = '',
    final InferenceVoiceOptions? voiceOptions,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
    final List<Object> contextFragments = const [],
  }) => InferenceRequest(
    prompt: text,
    contextFragments: contextFragments,
    systemPrompt: systemPrompt,
    workingDirectory: workingDirectory,
    metadata: metadata,
    task: InferenceTask.textToSpeech,
    voiceOptions: voiceOptions,
  );

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
}

class InferenceResponse {
  const InferenceResponse({
    required this.output,
    this.rawOutput,
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

  factory InferenceResponse.fromJson(final Map<String, dynamic> json) =>
      InferenceResponse(
        output: jsonDecodeMap(json['output']),
        rawOutput: jsonDecodeString(json['raw_output']),
        warnings: jsonDecodeListAs(json['warnings']),
        meta: jsonDecodeMap(json['meta']),
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

  final Map<String, dynamic> output;
  final String? rawOutput;
  final List<String> warnings;
  final Map<String, dynamic> meta;
  final InferenceTask task;
  final String? transcript;
  final String? normalizedTranscript;
  final List<InferenceSpeechSegment> segments;
  final InferenceAudioArtifact? audioArtifact;
  final List<({String name, dynamic output})> toolResults;

  /// Structured tool calls parsed by the inference client.
  ///
  /// Backends with native tool calling (OpenRouter, OpenAI, Apple Foundation)
  /// return parsed calls here directly — no tag round-trip. Raw/legacy backends
  /// that emit `<call|...>` tags in [rawOutput] leave this empty; the harness
  /// falls back to tag parsing for those.
  final List<({String name, Map<String, dynamic> arguments})> toolCalls;

  Map<String, dynamic> toJson() => {
    'task': task.name,
    'output': output,
    if (rawOutput != null) 'raw_output': rawOutput,
    if (transcript != null) 'transcript': transcript,
    if (normalizedTranscript != null)
      'normalized_transcript': normalizedTranscript,
    if (segments.isNotEmpty)
      'segments': segments.map((final segment) => segment.toJson()).toList(),
    if (audioArtifact != null) 'audio_artifact': audioArtifact!.toJson(),
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

  factory InferenceAudioInput.fromJson(final Map<String, dynamic> json) =>
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

  factory InferenceAudioArtifact.fromJson(final Map<String, dynamic> json) =>
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

  factory InferenceSpeechSegment.fromJson(final Map<String, dynamic> json) =>
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

  factory InferenceVoiceOptions.fromJson(final Map<String, dynamic> json) =>
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
