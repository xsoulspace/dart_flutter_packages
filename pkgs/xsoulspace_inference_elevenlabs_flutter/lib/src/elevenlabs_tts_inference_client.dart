import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'elevenlabs_common.dart';
import 'elevenlabs_config.dart';

class ElevenLabsTtsInferenceClient implements InferenceClient {
  ElevenLabsTtsInferenceClient({
    required final ElevenLabsAuthConfig authConfig,
    final ElevenLabsEndpointConfig? endpointConfig,
    final http.Client? httpClient,
    DateTime Function()? now,
  }) : _authConfig = authConfig,
       _endpointConfig = endpointConfig ?? ElevenLabsEndpointConfig(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _now = now ?? DateTime.now;

  final ElevenLabsAuthConfig _authConfig;
  final ElevenLabsEndpointConfig _endpointConfig;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _now;

  @override
  String get id => 'elevenlabs_tts';

  @override
  bool get isAvailable => true;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.textToSpeech,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {
    // No availability cache; API key checks happen during infer.
  }

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

    final voiceId = nonEmptyString(request.voiceOptions?.voiceId);
    if (voiceId == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'request_invalid',
        message: 'TTS request requires voiceOptions.voiceId',
        details: const <String, dynamic>{'reason': 'voice_id_missing'},
      );
    }

    final providerExtras =
        request.voiceOptions?.providerExtras ?? const <String, dynamic>{};
    final outputFormat =
        nonEmptyString(providerExtras['output_format']) ?? 'mp3_44100_128';
    final outputPath = resolveOutputPath(
      workingDirectory: request.workingDirectory,
      metadata: request.metadata,
      defaultPrefix: 'tts',
      timestamp: _now(),
      outputFormat: outputFormat,
    );

    final uri = _endpointConfig.resolveHttpPath(
      '/v1/text-to-speech/$voiceId',
      query: _buildQuery(providerExtras, outputFormat),
    );

    final body = <String, dynamic>{
      'text': request.prompt,
      if (nonEmptyString(providerExtras['model_id']) case final String modelId)
        'model_id': modelId,
      if (nonEmptyString(providerExtras['language_code'])
          case final String languageCode)
        'language_code': languageCode,
      if (intFromMap(providerExtras, 'seed') case final int seed) 'seed': seed,
      if (_buildVoiceSettings(providerExtras)
          case final Map<String, dynamic> voiceSettings)
        'voice_settings': voiceSettings,
      if (nonEmptyString(providerExtras['apply_text_normalization'])
          case final String applyTextNormalization)
        'apply_text_normalization': applyTextNormalization,
      if (nonEmptyString(providerExtras['apply_language_text_normalization'])
          case final String applyLanguageTextNormalization)
        'apply_language_text_normalization': applyLanguageTextNormalization,
    };

    try {
      final response = await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'xi-api-key': apiKey,
              'content-type': 'application/json',
              'accept': 'application/octet-stream',
            },
            body: jsonEncode(body),
          )
          .timeout(_endpointConfig.timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return InferenceResult<InferenceResponse>.fail(
          code: mapElevenLabsHttpStatusToCode(response.statusCode),
          message: messageFromElevenLabsErrorBody(
            bodyBytes: response.bodyBytes,
            fallback:
                'ElevenLabs TTS request failed with status ${response.statusCode}',
          ),
          details: detailsFromElevenLabsErrorBody(response.bodyBytes),
          meta: <String, dynamic>{
            'provider': id,
            'http_status': response.statusCode,
          },
        );
      }

      if (response.bodyBytes.isEmpty) {
        return InferenceResult<InferenceResponse>.fail(
          code: errorCodeAudioOutputUnavailable,
          message: 'ElevenLabs TTS returned empty audio payload',
          meta: <String, dynamic>{'provider': id, 'voice_id': voiceId},
        );
      }

      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(response.bodyBytes, flush: true);

      final explicitMimeType = nonEmptyString(
        request.metadata['output_mime_type'],
      );
      final mimeType = explicitMimeType ?? mimeTypeFromOutputPath(outputPath);
      final modelId = nonEmptyString(providerExtras['model_id']);
      final requestId =
          caseInsensitiveHeader(response.headers, 'request-id') ??
          caseInsensitiveHeader(response.headers, 'x-request-id');

      final responseMeta = <String, dynamic>{
        'provider': id,
        'voice_id': voiceId,
        'output_format': outputFormat,
        if (modelId case final String modelIdValue) 'model_id': modelIdValue,
        if (requestId case final String requestIdValue)
          'request_id': requestIdValue,
      };

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          task: InferenceTask.textToSpeech,
          output: const <String, dynamic>{},
          audioArtifact: InferenceAudioArtifact(
            filePath: outputPath,
            mimeType: mimeType,
          ),
          meta: responseMeta,
        ),
        meta: responseMeta,
      );
    } on TimeoutException catch (_) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs TTS request timed out',
        meta: const <String, dynamic>{'provider': 'elevenlabs_tts'},
      );
    } on SocketException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs TTS network connection failed',
        details: error.toString(),
        meta: const <String, dynamic>{'provider': 'elevenlabs_tts'},
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'ElevenLabs TTS failed unexpectedly',
        details: error.toString(),
        meta: const <String, dynamic>{'provider': 'elevenlabs_tts'},
      );
    }
  }

  Map<String, String> _buildQuery(
    final Map<String, dynamic> providerExtras,
    final String outputFormat,
  ) {
    final query = <String, String>{'output_format': outputFormat};

    if (boolFromMap(providerExtras, 'enable_logging') case final bool enabled) {
      query['enable_logging'] = enabled.toString();
    }

    if (intFromMap(providerExtras, 'optimize_streaming_latency')
        case final int optimizeStreamingLatency) {
      query['optimize_streaming_latency'] = optimizeStreamingLatency.toString();
    }

    return query;
  }

  Map<String, dynamic>? _buildVoiceSettings(
    final Map<String, dynamic> providerExtras,
  ) {
    final voiceSettings = <String, dynamic>{
      if (doubleFromMap(providerExtras, 'stability')
          case final double stability)
        'stability': stability,
      if (doubleFromMap(providerExtras, 'similarity_boost')
          case final double similarityBoost)
        'similarity_boost': similarityBoost,
      if (doubleFromMap(providerExtras, 'style') case final double style)
        'style': style,
      if (doubleFromMap(providerExtras, 'speed') case final double speed)
        'speed': speed,
      if (boolFromMap(providerExtras, 'use_speaker_boost')
          case final bool useSpeakerBoost)
        'use_speaker_boost': useSpeakerBoost,
    };

    if (voiceSettings.isEmpty) {
      return null;
    }

    return voiceSettings;
  }
}
