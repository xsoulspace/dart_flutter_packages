import 'dart:convert';

import 'package:path/path.dart' as p;

const String errorCodeAuthFailed = 'auth_failed';
const String errorCodeResourceNotFound = 'resource_not_found';

String mapElevenLabsHttpStatusToCode(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    return errorCodeAuthFailed;
  }
  if (statusCode == 404) {
    return errorCodeResourceNotFound;
  }
  if (statusCode == 400 || statusCode == 422) {
    return 'request_invalid';
  }
  if (statusCode == 408 || statusCode == 429 || statusCode >= 500) {
    return 'engine_unavailable';
  }
  return 'engine_unavailable';
}

String messageFromElevenLabsErrorBody({
  required List<int> bodyBytes,
  required String fallback,
}) {
  if (bodyBytes.isEmpty) {
    return fallback;
  }

  try {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
      if (detail is Map<String, dynamic>) {
        final message = detail['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
      final error = decoded['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }
    }
  } catch (_) {
    // Ignore JSON decode failures and use fallback.
  }

  return fallback;
}

Object? detailsFromElevenLabsErrorBody(List<int> bodyBytes) {
  if (bodyBytes.isEmpty) {
    return null;
  }

  try {
    return jsonDecode(utf8.decode(bodyBytes));
  } catch (_) {
    return utf8.decode(bodyBytes, allowMalformed: true);
  }
}

String? nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  return trimmed;
}

bool? boolFromMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true') {
      return true;
    }
    if (lower == 'false') {
      return false;
    }
  }
  return null;
}

double? doubleFromMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

int? intFromMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String mimeTypeFromOutputPath(String outputPath) {
  final lower = outputPath.toLowerCase();
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.ulaw')) return 'audio/basic';
  if (lower.endsWith('.pcm')) return 'audio/pcm';
  return 'audio/octet-stream';
}

String extensionFromOutputFormat(String outputFormat) {
  if (outputFormat.startsWith('mp3_')) {
    return '.mp3';
  }
  if (outputFormat.startsWith('pcm_')) {
    return '.pcm';
  }
  if (outputFormat.startsWith('ulaw_')) {
    return '.ulaw';
  }
  if (outputFormat.startsWith('alaw_')) {
    return '.wav';
  }
  return '.mp3';
}

String resolveOutputPath({
  required String workingDirectory,
  required Map<String, dynamic> metadata,
  required String defaultPrefix,
  required DateTime timestamp,
  required String outputFormat,
}) {
  final explicit = nonEmptyString(metadata['output_file_path']);
  if (explicit != null) {
    return explicit;
  }

  final extension = extensionFromOutputFormat(outputFormat);
  return p.join(
    workingDirectory,
    '${defaultPrefix}_${timestamp.millisecondsSinceEpoch}$extension',
  );
}

String? caseInsensitiveHeader(
  Map<String, String> headers,
  String key,
) {
  final target = key.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return null;
}

Map<String, dynamic> mapWithStringKeys(Object? value) {
  if (value is Map) {
    return value.map(
      (dynamic key, dynamic value) =>
          MapEntry(key.toString(), value),
    );
  }
  return const <String, dynamic>{};
}
