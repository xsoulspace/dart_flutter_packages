import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'elevenlabs_common.dart';
import 'elevenlabs_config.dart';

class ElevenLabsSttInferenceClient implements InferenceClient {
  ElevenLabsSttInferenceClient({
    required final ElevenLabsAuthConfig authConfig,
    final ElevenLabsEndpointConfig? endpointConfig,
    final http.Client? httpClient,
  }) : _authConfig = authConfig,
       _endpointConfig = endpointConfig ?? ElevenLabsEndpointConfig(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final ElevenLabsAuthConfig _authConfig;
  final ElevenLabsEndpointConfig _endpointConfig;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  @override
  String get id => 'elevenlabs_stt';

  @override
  bool get isAvailable => true;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.speechToText,
  };

  Future<void> dispose() async {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request,
  ) async {
    if (!supportedTasks.contains(request.task)) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Task ${request.task.name} is not supported by $id',
        details: <String, dynamic>{
          'supported_tasks': supportedTasks
              .map((final task) => task.name)
              .toList(),
          'requested_task': request.task.name,
        },
      );
    }

    final requestValidation = validateInferenceRequest(request);
    if (!requestValidation.success) {
      return InferenceResult<InferenceResponse>.fail(
        code: requestValidation.error?.code ?? 'request_invalid',
        message:
            requestValidation.error?.message ??
            'Inference request validation failed',
        details: requestValidation.error?.details,
      );
    }

    final apiKey = _authConfig.normalizedApiKey;
    if (apiKey == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeAuthFailed,
        message: '$id requires ElevenLabs API key for HTTP inference',
      );
    }

    final audioInput = request.audioInput;
    if (audioInput == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeAudioInputMissing,
        message: 'Speech-to-text request requires audioInput',
      );
    }

    final source = audioInput.resolvedSource;
    if (source == InferenceAudioSource.microphone) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeTaskUnsupported,
        message: 'Microphone STT requires realtime websocket session',
        details: const <String, dynamic>{
          'reason': 'microphone_requires_realtime_session',
        },
      );
    }

    if (source == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: errorCodeAudioInputInvalid,
        message: 'Audio input source could not be resolved',
      );
    }

    final metadata = request.metadata;
    final query = <String, String>{};
    final enableLogging = boolFromMap(metadata, 'enable_logging');
    if (enableLogging != null) {
      query['enable_logging'] = enableLogging.toString();
    }

    final uri = _endpointConfig.resolveHttpPath(
      '/v1/speech-to-text',
      query: query,
    );

    try {
      final multipartRequest = http.MultipartRequest('POST', uri)
        ..headers['xi-api-key'] = apiKey
        ..headers['accept'] = 'application/json'
        ..fields['model_id'] =
            nonEmptyString(metadata['model_id']) ?? 'scribe_v1';

      if (nonEmptyString(metadata['language_code'])
          case final String languageCode) {
        multipartRequest.fields['language_code'] = languageCode;
      }

      if (boolFromMap(metadata, 'diarize') case final bool diarize) {
        multipartRequest.fields['diarize'] = diarize.toString();
      }

      if (boolFromMap(metadata, 'tag_audio_events')
          case final bool tagAudioEvents) {
        multipartRequest.fields['tag_audio_events'] = tagAudioEvents.toString();
      }

      final timestampsGranularity = _resolveTimestampsGranularity(metadata);
      if (timestampsGranularity != null) {
        multipartRequest.fields['timestamps_granularity'] =
            timestampsGranularity;
      }

      final fileResult = await _buildMultipartAudio(audioInput);
      if (!fileResult.success || fileResult.data == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: fileResult.error?.code ?? errorCodeAudioInputInvalid,
          message:
              fileResult.error?.message ??
              'Failed to prepare audio input for ElevenLabs STT',
          details: fileResult.error?.details,
        );
      }

      multipartRequest.files.add(fileResult.data!);

      final streamedResponse = await _httpClient
          .send(multipartRequest)
          .timeout(_endpointConfig.timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return InferenceResult<InferenceResponse>.fail(
          code: mapElevenLabsHttpStatusToCode(response.statusCode),
          message: messageFromElevenLabsErrorBody(
            bodyBytes: response.bodyBytes,
            fallback:
                'ElevenLabs STT request failed with status ${response.statusCode}',
          ),
          details: detailsFromElevenLabsErrorBody(response.bodyBytes),
          meta: <String, dynamic>{
            'provider': id,
            'http_status': response.statusCode,
          },
        );
      }

      final decoded = jsonDecode(response.body) as Object?;
      if (decoded is! Map<String, dynamic>) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'engine_unavailable',
          message: 'ElevenLabs STT response was not a JSON object',
          details: response.body,
          meta: const <String, dynamic>{'provider': 'elevenlabs_stt'},
        );
      }

      final transcript = _resolveTranscript(decoded);
      final normalizedTranscript = normalizeTranscript(transcript);
      final segments = _resolveSegments(decoded, transcript);

      final responseMeta = <String, dynamic>{
        'provider': id,
        if (nonEmptyString(decoded['language_code'])
            case final String languageCode)
          'language_code': languageCode,
        if (nonEmptyString(decoded['transcription_id'])
            case final String transcriptionId)
          'transcription_id': transcriptionId,
      };

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.speechToText,
          output: const <String, dynamic>{},
          transcript: transcript,
          normalizedTranscript: normalizedTranscript,
          segments: segments,
          meta: responseMeta,
        ),
        meta: responseMeta,
      );
    } on SocketException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs STT network connection failed',
        details: error.toString(),
        meta: const <String, dynamic>{'provider': 'elevenlabs_stt'},
      );
    } on TimeoutException catch (_) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs STT request timed out',
        meta: const <String, dynamic>{'provider': 'elevenlabs_stt'},
      );
    } on FormatException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs STT returned malformed JSON',
        details: error.toString(),
        meta: const <String, dynamic>{'provider': 'elevenlabs_stt'},
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs STT failed unexpectedly',
        details: error.toString(),
        meta: const <String, dynamic>{'provider': 'elevenlabs_stt'},
      );
    }
  }

  Future<InferenceResult<http.MultipartFile>> _buildMultipartAudio(
    final InferenceAudioInput input,
  ) async {
    final source = input.resolvedSource;
    if (source == InferenceAudioSource.filePath) {
      final path = nonEmptyString(input.filePath);
      if (path == null) {
        return InferenceResult<http.MultipartFile>.fail(
          code: errorCodeAudioInputInvalid,
          message: 'Audio file path must not be empty',
        );
      }

      final file = File(path);
      if (!await file.exists()) {
        return InferenceResult<http.MultipartFile>.fail(
          code: errorCodeAudioInputInvalid,
          message: 'Audio file does not exist: $path',
        );
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return InferenceResult<http.MultipartFile>.fail(
          code: errorCodeAudioInputInvalid,
          message: 'Audio file is empty: $path',
        );
      }

      return InferenceResult<http.MultipartFile>.ok(
        http.MultipartFile.fromBytes('file', bytes, filename: p.basename(path)),
      );
    }

    if (source == InferenceAudioSource.bytes) {
      final bytes = input.bytes ?? const <int>[];
      if (bytes.isEmpty) {
        return InferenceResult<http.MultipartFile>.fail(
          code: errorCodeAudioInputInvalid,
          message: 'Audio bytes input must not be empty',
        );
      }

      return InferenceResult<http.MultipartFile>.ok(
        http.MultipartFile.fromBytes('file', bytes, filename: 'input_audio'),
      );
    }

    return InferenceResult<http.MultipartFile>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Unsupported audio source for ElevenLabs STT',
      details: const <String, dynamic>{'reason': 'unsupported_source'},
    );
  }

  String? _resolveTimestampsGranularity(final Map<String, dynamic> metadata) {
    final direct = nonEmptyString(metadata['timestamps_granularity']);
    if (direct != null) {
      return direct;
    }

    final value = metadata['timestamps_granularity'];
    if (value is List) {
      for (final item in value) {
        final parsed = nonEmptyString(item);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  String _resolveTranscript(final Map<String, dynamic> json) {
    final direct = nonEmptyString(json['text']);
    if (direct != null) {
      return direct;
    }

    final transcripts = json['transcripts'];
    if (transcripts is List) {
      final chunks = <String>[];
      for (final item in transcripts) {
        final map = mapWithStringKeys(item);
        final text = nonEmptyString(map['text']);
        if (text != null) {
          chunks.add(text);
        }
      }
      if (chunks.isNotEmpty) {
        return chunks.join('\n');
      }
    }

    return '';
  }

  List<InferenceSpeechSegment> _resolveSegments(
    final Map<String, dynamic> json,
    final String transcript,
  ) {
    final words = <Map<String, dynamic>>[];

    final directWords = json['words'];
    if (directWords is List) {
      for (final item in directWords) {
        final map = mapWithStringKeys(item);
        if (map.isNotEmpty) {
          words.add(map);
        }
      }
    }

    final transcripts = json['transcripts'];
    if (transcripts is List) {
      for (final item in transcripts) {
        final map = mapWithStringKeys(item);
        final transcriptWords = map['words'];
        if (transcriptWords is List) {
          for (final word in transcriptWords) {
            final wordMap = mapWithStringKeys(word);
            if (wordMap.isNotEmpty) {
              words.add(wordMap);
            }
          }
        }
      }
    }

    final segments = <InferenceSpeechSegment>[];
    for (final word in words) {
      final text = nonEmptyString(word['text']);
      if (text == null) {
        continue;
      }
      final startSeconds = word['start'];
      final endSeconds = word['end'];
      final startMs = startSeconds is num ? (startSeconds * 1000).round() : 0;
      final endMs = endSeconds is num ? (endSeconds * 1000).round() : startMs;
      segments.add(
        InferenceSpeechSegment(text: text, startMs: startMs, endMs: endMs),
      );
    }

    if (segments.isNotEmpty) {
      return segments;
    }

    if (transcript.trim().isEmpty) {
      return const <InferenceSpeechSegment>[];
    }

    return <InferenceSpeechSegment>[
      InferenceSpeechSegment(text: transcript, startMs: 0, endMs: 0),
    ];
  }
}
