import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:recase/recase.dart';

import 'prompt_builder.dart';

/// The idea is that inference task should be as atomic as possible
/// so if structural output is needed it should be pointed as such
/// or relevant config for API passed.
enum InferenceTask {
  text,

  /// text will depend from [PromptBuilder.structuredOutputSystemPrompt],
  /// even if parameters doesnt set to return structured output.
  ///
  // TODO(arenukvern): rework as fallback strategy
  implicitlyStructuredText,
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
/// TODO: make it more native for convertion fragments -> transcript
class InferenceRequest {
  const InferenceRequest({
    required this.prompt,
    required this.outputSchema,
    required this.workingDirectory,
    this.systemPrompt = '',
    this.contextFragments = const [],
    this.metadata = const <String, dynamic>{},
    this.task = InferenceTask.text,
    this.audioInput,
    this.voiceOptions,
  });

  factory InferenceRequest.fromJson(final Map<String, dynamic> json) =>
      InferenceRequest(
        prompt: jsonEncodeString(json['prompt']) ?? '',
        outputSchema: jsonDecodeMap(json['output_schema']),
        contextFragments: jsonDecodeListAs<Object>(json['context_fragments']),
        workingDirectory: jsonEncodeString(json['working_directory']),
        metadata: jsonDecodeMap(json['metadata']),
        systemPrompt: jsonEncodeString(json['system_prompt']),
        task: InferenceTask.fromJson(json['task']),
        audioInput: switch (json['audio_input']) {
          final Map value => InferenceAudioInput.fromJson(
            value.cast<String, dynamic>(),
          ),
          _ => null,
        },
        voiceOptions: switch (json['voice_options']) {
          final Map value => InferenceVoiceOptions.fromJson(
            value.cast<String, dynamic>(),
          ),
          _ => null,
        },
      );

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
    outputSchema: const <String, dynamic>{},
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
    outputSchema: const <String, dynamic>{},
    workingDirectory: workingDirectory,
    metadata: metadata,
    task: InferenceTask.textToSpeech,
    voiceOptions: voiceOptions,
  );

  final String prompt;
  final Map<String, dynamic> outputSchema;
  final String workingDirectory;
  final Map<String, dynamic> metadata;
  final InferenceTask task;
  final InferenceAudioInput? audioInput;
  final InferenceVoiceOptions? voiceOptions;
  final List<Object> contextFragments;
  final String systemPrompt;
  String get contextFragmentsJson =>
      contextFragments.isNotEmpty ? jsonEncode(contextFragments) : '';

  Map<String, dynamic> toJson() => {
    'task': task.name,
    'prompt': prompt,
    'output_schema': outputSchema,
    'working_directory': workingDirectory,
    'system_prompt': systemPrompt,
    'context_fragments': jsonEncode(contextFragments),
    'metadata': metadata,
    'audio_input': ?audioInput?.toJson(),
    'voice_options': ?voiceOptions?.toJson(),
  };
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
        filePath: jsonEncodeString(json['file_path']),
        bytes: switch (json['bytes_base64']) {
          final String value => base64Decode(value),
          _ => null,
        },
        mimeType: jsonEncodeString(json['mime_type']),
        sampleRateHz: jsonEncodeInt(json['sample_rate_hz']),
        channelCount: jsonEncodeInt(json['channel_count']),
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
        filePath: jsonEncodeString(json['file_path']),
        mimeType: jsonEncodeString(json['mime_type']),
        durationMs: jsonEncodeInt(json['duration_ms']),
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
        text: jsonEncodeString(json['text']),
        startMs: jsonEncodeInt(json['start_ms']),
        endMs: jsonEncodeInt(json['end_ms']),
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
        voiceId: jsonEncodeString(json['voice_id']),
        locale: jsonEncodeString(json['locale']),
        speechRate: jsonEncodeDouble(json['speech_rate']),
        pitch: jsonEncodeDouble(json['pitch']),
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
