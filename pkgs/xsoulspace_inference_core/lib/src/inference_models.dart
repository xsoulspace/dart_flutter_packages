import 'dart:convert';

enum InferenceTask { structuredText, speechToText, textToSpeech }

InferenceTask inferenceTaskFromJsonValue(final Object? value) {
  if (value is! String) {
    return InferenceTask.structuredText;
  }

  for (final task in InferenceTask.values) {
    if (task.name == value) {
      return task;
    }
  }

  return InferenceTask.structuredText;
}

enum InferenceAudioSource { filePath, bytes, microphone }

String inferenceAudioSourceToJsonValue(final InferenceAudioSource source) =>
    switch (source) {
      InferenceAudioSource.filePath => 'file_path',
      InferenceAudioSource.bytes => 'bytes',
      InferenceAudioSource.microphone => 'microphone',
    };

InferenceAudioSource? inferenceAudioSourceFromJsonValue(final Object? value) {
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

class InferenceAudioInput {
  const InferenceAudioInput({
    this.source,
    this.filePath,
    this.bytes,
    required this.mimeType,
    this.sampleRateHz,
    this.channelCount,
  });

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
      'source': inferenceAudioSourceToJsonValue(resolvedSource!),
    if (filePath != null) 'file_path': filePath,
    if (bytes != null) 'bytes_base64': base64Encode(bytes!),
    'mime_type': mimeType,
    if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
    if (channelCount != null) 'channel_count': channelCount,
  };

  factory InferenceAudioInput.fromJson(final Map<String, dynamic> json) =>
      InferenceAudioInput(
        source: inferenceAudioSourceFromJsonValue(json['source']),
        filePath: json['file_path'] as String?,
        bytes: switch (json['bytes_base64']) {
          final String value => base64Decode(value),
          _ => null,
        },
        mimeType: (json['mime_type'] as String?) ?? '',
        sampleRateHz: json['sample_rate_hz'] as int?,
        channelCount: json['channel_count'] as int?,
      );
}

class InferenceAudioArtifact {
  const InferenceAudioArtifact({
    required this.filePath,
    required this.mimeType,
    this.durationMs,
  });

  final String filePath;
  final String mimeType;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
    'file_path': filePath,
    'mime_type': mimeType,
    if (durationMs != null) 'duration_ms': durationMs,
  };

  factory InferenceAudioArtifact.fromJson(final Map<String, dynamic> json) =>
      InferenceAudioArtifact(
        filePath: (json['file_path'] as String?) ?? '',
        mimeType: (json['mime_type'] as String?) ?? '',
        durationMs: json['duration_ms'] as int?,
      );
}

class InferenceSpeechSegment {
  const InferenceSpeechSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;

  Map<String, dynamic> toJson() => {
    'text': text,
    'start_ms': startMs,
    'end_ms': endMs,
  };

  factory InferenceSpeechSegment.fromJson(final Map<String, dynamic> json) =>
      InferenceSpeechSegment(
        text: (json['text'] as String?) ?? '',
        startMs: (json['start_ms'] as num?)?.round() ?? 0,
        endMs: (json['end_ms'] as num?)?.round() ?? 0,
      );
}

class InferenceVoiceOptions {
  const InferenceVoiceOptions({
    this.voiceId,
    this.locale,
    this.speechRate,
    this.pitch,
    this.providerExtras = const <String, dynamic>{},
  });

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

  factory InferenceVoiceOptions.fromJson(final Map<String, dynamic> json) =>
      InferenceVoiceOptions(
        voiceId: json['voice_id'] as String?,
        locale: json['locale'] as String?,
        speechRate: (json['speech_rate'] as num?)?.toDouble(),
        pitch: (json['pitch'] as num?)?.toDouble(),
        providerExtras:
            (json['provider_extras'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
}

class InferenceRequest {
  const InferenceRequest({
    required this.prompt,
    required this.outputSchema,
    required this.workingDirectory,
    this.metadata = const <String, dynamic>{},
    this.task = InferenceTask.structuredText,
    this.audioInput,
    this.voiceOptions,
  });

  factory InferenceRequest.speechToText({
    required final InferenceAudioInput audioInput,
    final String workingDirectory = '.',
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => InferenceRequest(
    prompt: '',
    outputSchema: const <String, dynamic>{},
    workingDirectory: workingDirectory,
    metadata: metadata,
    task: InferenceTask.speechToText,
    audioInput: audioInput,
  );

  factory InferenceRequest.textToSpeech({
    required final String text,
    final String workingDirectory = '.',
    final InferenceVoiceOptions? voiceOptions,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => InferenceRequest(
    prompt: text,
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

  Map<String, dynamic> toJson() => {
    'task': task.name,
    'prompt': prompt,
    'output_schema': outputSchema,
    'working_directory': workingDirectory,
    'metadata': metadata,
    if (audioInput != null) 'audio_input': audioInput!.toJson(),
    if (voiceOptions != null) 'voice_options': voiceOptions!.toJson(),
  };

  factory InferenceRequest.fromJson(final Map<String, dynamic> json) =>
      InferenceRequest(
        prompt: (json['prompt'] as String?) ?? '',
        outputSchema:
            (json['output_schema'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        workingDirectory: (json['working_directory'] as String?) ?? '',
        metadata:
            (json['metadata'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        task: inferenceTaskFromJsonValue(json['task']),
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
}

class InferenceResponse {
  const InferenceResponse({
    required this.output,
    this.rawOutput,
    this.warnings = const <String>[],
    this.meta = const <String, dynamic>{},
    this.task = InferenceTask.structuredText,
    this.transcript,
    this.normalizedTranscript,
    this.segments = const <InferenceSpeechSegment>[],
    this.audioArtifact,
  });

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

  factory InferenceResponse.fromJson(final Map<String, dynamic> json) =>
      InferenceResponse(
        output:
            (json['output'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        rawOutput: json['raw_output'] as String?,
        warnings:
            (json['warnings'] as List?)?.cast<String>() ?? const <String>[],
        meta:
            (json['meta'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        task: inferenceTaskFromJsonValue(json['task']),
        transcript: json['transcript'] as String?,
        normalizedTranscript: json['normalized_transcript'] as String?,
        segments:
            (json['segments'] as List?)
                ?.map(
                  (final segment) => InferenceSpeechSegment.fromJson(
                    (segment as Map).cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false) ??
            const <InferenceSpeechSegment>[],
        audioArtifact: switch (json['audio_artifact']) {
          final Map value => InferenceAudioArtifact.fromJson(
            value.cast<String, dynamic>(),
          ),
          _ => null,
        },
      );
}
