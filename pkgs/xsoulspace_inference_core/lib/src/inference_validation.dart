import 'dart:convert';

import 'inference_models.dart';
import 'inference_result.dart';

const String errorCodeTaskUnsupported = 'task_unsupported';
const String errorCodeAudioInputMissing = 'audio_input_missing';
const String errorCodeAudioInputInvalid = 'audio_input_invalid';
const String errorCodeTtsTextEmpty = 'tts_text_empty';
const String errorCodeAudioOutputUnavailable = 'audio_output_unavailable';

InferenceResult<Map<String, dynamic>> parseStrictJsonObject(final String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return InferenceResult<Map<String, dynamic>>.fail(
      code: 'json_empty',
      message: 'Expected JSON object but got empty output',
    );
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      return InferenceResult<Map<String, dynamic>>.fail(
        code: 'json_not_object',
        message: 'Expected top-level JSON object',
        details: decoded.runtimeType.toString(),
      );
    }
    return InferenceResult<Map<String, dynamic>>.ok(decoded);
  } catch (error) {
    return InferenceResult<Map<String, dynamic>>.fail(
      code: 'json_parse_failed',
      message: 'Failed to parse JSON output',
      details: error.toString(),
    );
  }
}

InferenceResult<void> validateRequiredKeys({
  required final Map<String, dynamic> object,
  required final Iterable<String> requiredKeys,
}) {
  final missing = <String>[];
  for (final key in requiredKeys) {
    final value = object[key];
    if (value == null) {
      missing.add(key);
    }
  }

  if (missing.isNotEmpty) {
    return InferenceResult<void>.fail(
      code: 'required_keys_missing',
      message: 'Missing required keys in inference output',
      details: <String, dynamic>{'missing_keys': missing},
    );
  }

  return InferenceResult<void>.ok(null);
}

InferenceResult<void> validateInferenceRequest(final InferenceRequest request) {
  if (request.workingDirectory.trim().isEmpty) {
    return InferenceResult<void>.fail(
      code: 'request_working_directory_empty',
      message: 'Inference workingDirectory must not be empty',
    );
  }

  switch (request.task) {
    case InferenceTask.structuredText:
      if (request.prompt.trim().isEmpty) {
        return InferenceResult<void>.fail(
          code: 'request_prompt_empty',
          message: 'Inference prompt must not be empty',
        );
      }

      if (request.outputSchema.isEmpty) {
        return InferenceResult<void>.fail(
          code: 'request_schema_empty',
          message: 'Inference outputSchema must not be empty',
        );
      }

      return validateSchemaDefinition(request.outputSchema);
    case InferenceTask.speechToText:
      final audioInput = request.audioInput;
      if (audioInput == null) {
        return InferenceResult<void>.fail(
          code: errorCodeAudioInputMissing,
          message: 'Speech-to-text request requires audioInput',
        );
      }
      return validateInferenceAudioInput(audioInput);
    case InferenceTask.textToSpeech:
      if (request.prompt.trim().isEmpty) {
        return InferenceResult<void>.fail(
          code: errorCodeTtsTextEmpty,
          message: 'Text-to-speech request text must not be empty',
        );
      }
      return InferenceResult<void>.ok(null);
  }
}

InferenceResult<void> validateInferenceAudioInput(
  final InferenceAudioInput audioInput,
) {
  final hasFilePath = (audioInput.filePath ?? '').trim().isNotEmpty;
  final hasBytes = (audioInput.bytes ?? const <int>[]).isNotEmpty;
  final source = audioInput.resolvedSource;

  if (source == InferenceAudioSource.microphone && (hasFilePath || hasBytes)) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Microphone audio input must not provide filePath or bytes',
      details: const <String, dynamic>{'reason': 'microphone_source_ambiguous'},
    );
  }

  if (source == InferenceAudioSource.filePath && !hasFilePath) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input source=file_path requires filePath',
      details: const <String, dynamic>{'reason': 'source_mismatch'},
    );
  }

  if (source == InferenceAudioSource.bytes && !hasBytes) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input source=bytes requires bytes',
      details: const <String, dynamic>{'reason': 'source_mismatch'},
    );
  }

  if (source != InferenceAudioSource.microphone && !hasFilePath && !hasBytes) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input must provide filePath, bytes, or microphone source',
      details: const <String, dynamic>{'reason': 'source_missing'},
    );
  }

  if (source != InferenceAudioSource.microphone && hasFilePath && hasBytes) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input must not provide both filePath and bytes',
      details: const <String, dynamic>{'reason': 'ambiguous_source'},
    );
  }

  if (audioInput.mimeType.trim().isEmpty) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input mimeType must not be empty',
      details: const <String, dynamic>{'reason': 'mime_type_empty'},
    );
  }

  final sampleRateHz = audioInput.sampleRateHz;
  if (sampleRateHz != null && sampleRateHz <= 0) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input sampleRateHz must be > 0 when provided',
      details: const <String, dynamic>{'reason': 'sample_rate_invalid'},
    );
  }

  final channelCount = audioInput.channelCount;
  if (channelCount != null && channelCount <= 0) {
    return InferenceResult<void>.fail(
      code: errorCodeAudioInputInvalid,
      message: 'Audio input channelCount must be > 0 when provided',
      details: const <String, dynamic>{'reason': 'channel_count_invalid'},
    );
  }

  return InferenceResult<void>.ok(null);
}

String normalizeTranscript(final String transcript) {
  final punctuationStripped = transcript.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]+', unicode: true),
    ' ',
  );
  return punctuationStripped.replaceAll(RegExp(r'\s+'), ' ').trim();
}

InferenceResult<void> validateSchemaDefinition(
  final Map<String, dynamic> schema, {
  final String path = r'$',
}) {
  final rawType = schema['type'];
  if (rawType != null && rawType is! String) {
    return InferenceResult<void>.fail(
      code: 'schema_invalid_type_field',
      message: 'Schema "type" must be a string',
      details: <String, dynamic>{'path': path},
    );
  }

  final rawRequired = schema['required'];
  if (rawRequired != null &&
      (rawRequired is! List ||
          rawRequired.any((final key) => key is! String))) {
    return InferenceResult<void>.fail(
      code: 'schema_invalid_required_field',
      message: 'Schema "required" must be a list of strings',
      details: <String, dynamic>{'path': path},
    );
  }

  final rawProperties = schema['properties'];
  if (rawProperties != null && rawProperties is! Map<String, dynamic>) {
    return InferenceResult<void>.fail(
      code: 'schema_invalid_properties_field',
      message: 'Schema "properties" must be an object',
      details: <String, dynamic>{'path': path},
    );
  }

  if (rawProperties case final Map<String, dynamic> properties) {
    for (final entry in properties.entries) {
      if (entry.value is! Map<String, dynamic>) {
        return InferenceResult<void>.fail(
          code: 'schema_invalid_property_definition',
          message: 'Each property schema must be an object',
          details: <String, dynamic>{'path': '$path.properties.${entry.key}'},
        );
      }
      final nested = validateSchemaDefinition(
        entry.value as Map<String, dynamic>,
        path: '$path.properties.${entry.key}',
      );
      if (!nested.success) {
        return nested;
      }
    }
  }

  final rawItems = schema['items'];
  if (rawItems != null && rawItems is! Map<String, dynamic>) {
    return InferenceResult<void>.fail(
      code: 'schema_invalid_items_field',
      message: 'Schema "items" must be an object',
      details: <String, dynamic>{'path': path},
    );
  }

  if (rawItems case final Map<String, dynamic> itemsSchema) {
    final nested = validateSchemaDefinition(itemsSchema, path: '$path.items');
    if (!nested.success) {
      return nested;
    }
  }

  return InferenceResult<void>.ok(null);
}

InferenceResult<void> validateJsonAgainstSchema({
  required final Object? value,
  required final Map<String, dynamic> schema,
}) {
  final definitionValidation = validateSchemaDefinition(schema);
  if (!definitionValidation.success) {
    return definitionValidation;
  }
  return _validateJsonNode(value: value, schema: schema, path: r'$');
}

InferenceResult<void> _validateJsonNode({
  required final Object? value,
  required final Map<String, dynamic> schema,
  required final String path,
}) {
  final rawType = schema['type'];
  if (rawType is String) {
    final isTypeValid = switch (rawType) {
      'object' => value is Map<String, dynamic>,
      'array' => value is List<dynamic>,
      'string' => value is String,
      'number' => value is num,
      'integer' => value is int,
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    };
    if (!isTypeValid) {
      return InferenceResult<void>.fail(
        code: 'schema_type_mismatch',
        message: 'JSON value does not match schema type "$rawType"',
        details: <String, dynamic>{
          'path': path,
          'expected_type': rawType,
          'actual_type': value?.runtimeType.toString() ?? 'null',
        },
      );
    }
  }

  final rawEnum = schema['enum'];
  if (rawEnum is List && !rawEnum.contains(value)) {
    return InferenceResult<void>.fail(
      code: 'schema_enum_mismatch',
      message: 'JSON value is not in the allowed enum set',
      details: <String, dynamic>{'path': path, 'value': value},
    );
  }

  if (value case final Map<String, dynamic> objectValue) {
    final requiredKeys =
        (schema['required'] as List?)?.whereType<String>() ??
        const Iterable<String>.empty();
    final missing = requiredKeys
        .where((final key) => objectValue[key] == null)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return InferenceResult<void>.fail(
        code: 'schema_required_keys_missing',
        message: 'Missing required keys in JSON value',
        details: <String, dynamic>{'path': path, 'missing_keys': missing},
      );
    }

    final properties =
        (schema['properties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    for (final entry in properties.entries) {
      if (!objectValue.containsKey(entry.key)) {
        continue;
      }
      if (entry.value is! Map<String, dynamic>) {
        continue;
      }
      final nested = _validateJsonNode(
        value: objectValue[entry.key],
        schema: entry.value as Map<String, dynamic>,
        path: '$path.${entry.key}',
      );
      if (!nested.success) {
        return nested;
      }
    }
  }

  if (value case final List<dynamic> listValue) {
    if (schema['items'] case final Map<String, dynamic> itemsSchema) {
      for (var index = 0; index < listValue.length; index++) {
        final nested = _validateJsonNode(
          value: listValue[index],
          schema: itemsSchema,
          path: '$path[$index]',
        );
        if (!nested.success) {
          return nested;
        }
      }
    }
  }

  return InferenceResult<void>.ok(null);
}
