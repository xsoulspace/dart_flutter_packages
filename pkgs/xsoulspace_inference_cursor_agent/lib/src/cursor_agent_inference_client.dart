import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class CursorAgentInferenceClient implements InferenceClient {
  CursorAgentInferenceClient({
    this.binaryName = 'cursor-agent',
    this.environment,
    this.extraExecArgs = const <String>[],
    this.defaultModel,
    this.defaultReasoningEffort,
    this.executionTimeout = const Duration(minutes: 2),
    this.maxOutputBytes = 1024 * 1024,
    this.maxAttempts = 4,
    this.maxTimeoutRetries = 1,
    this.maxTransientRetries = 1,
    this.killGracePeriod = const Duration(milliseconds: 300),
  }) : assert(maxOutputBytes > 0),
       assert(maxAttempts > 0),
       assert(maxTimeoutRetries >= 0),
       assert(maxTransientRetries >= 0);

  final String binaryName;
  final Map<String, String>? environment;
  final List<String> extraExecArgs;
  final String? defaultModel;
  final String? defaultReasoningEffort;
  final Duration executionTimeout;
  final int maxOutputBytes;
  final int maxAttempts;
  final int maxTimeoutRetries;
  final int maxTransientRetries;
  final Duration killGracePeriod;

  @override
  String get id => 'cursor_agent';

  @override
  bool get isAvailable => _resolveBinaryPath() != null;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.structuredText,
  };

  @override
  Future<bool> refreshAvailability() async => isAvailable;

  @override
  void resetAvailabilityCache() {
    // No availability cache for cursor-agent binary resolution.
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

    final workingDirectory = Directory(request.workingDirectory);
    if (!workingDirectory.existsSync()) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'working_directory_not_found',
        message: 'Inference working directory does not exist',
        details: request.workingDirectory,
      );
    }

    final binaryPath = _resolveBinaryPath();
    if (binaryPath == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'cursor-agent binary not found in PATH',
      );
    }

    try {
      final warnings = <String>[];
      var timeoutRetriesLeft = maxTimeoutRetries;
      var transientRetriesLeft = maxTransientRetries;
      final attempts = <_ExecRunResult>[];

      while (attempts.length < maxAttempts) {
        final result = await _runExec(binaryPath: binaryPath, request: request);
        attempts.add(result);

        if (result.exitCode == 0 && !result.timedOut) {
          break;
        }

        if (result.timedOut && timeoutRetriesLeft > 0) {
          timeoutRetriesLeft--;
          warnings.add('Retrying cursor-agent after timeout.');
          continue;
        }

        if (_isTransientFailure(result) && transientRetriesLeft > 0) {
          transientRetriesLeft--;
          warnings.add(
            'Retrying cursor-agent after transient process failure.',
          );
          continue;
        }

        break;
      }

      if (attempts.isEmpty) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'cursor_exec_failed',
          message: 'cursor-agent was not attempted',
        );
      }

      final result = attempts.last;
      if (result.exitCode != 0) {
        final authFailure = _isAuthFailure(result);
        final code = result.timedOut
            ? 'cursor_exec_timeout'
            : authFailure
            ? 'cursor_auth_failed'
            : 'cursor_exec_failed';
        final message = result.timedOut
            ? 'cursor-agent timed out after ${executionTimeout.inMilliseconds}ms'
            : authFailure
            ? 'cursor-agent authentication failed; use CURSOR_API_KEY or cursor-agent login'
            : 'cursor-agent failed with exit code ${result.exitCode}';
        return InferenceResult<InferenceResponse>.fail(
          code: code,
          message: message,
          details: _buildFailureDetails(
            result: result,
            attempts: attempts,
            authFailure: authFailure,
          ),
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
      }

      final rawOutputResult = _readRawOutput(stdout: result.stdout);
      if (!rawOutputResult.success || rawOutputResult.data == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: rawOutputResult.error?.code ?? 'cursor_output_invalid',
          message:
              rawOutputResult.error?.message ??
              'Failed to read cursor-agent output',
          details: rawOutputResult.error?.details,
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
      }

      final rawOutput = rawOutputResult.data!;
      final normalizedAssistantText = _normalizeAssistantText(
        rawOutput.assistantText,
      );
      final parsed = parseStrictJsonObject(normalizedAssistantText);
      if (!parsed.success || parsed.data == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: parsed.error?.code ?? 'json_parse_failed',
          message:
              parsed.error?.message ??
              'Failed to parse structured output from cursor-agent',
          details: parsed.error?.details ?? _truncate(normalizedAssistantText),
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
      }

      final normalizedOutput = _normalizeForSchema(
        parsed.data!,
        request.outputSchema,
      );

      final schemaValidation = validateJsonAgainstSchema(
        value: normalizedOutput,
        schema: request.outputSchema,
      );
      if (!schemaValidation.success) {
        return InferenceResult<InferenceResponse>.fail(
          code: schemaValidation.error?.code ?? 'schema_validation_failed',
          message:
              schemaValidation.error?.message ??
              'Inference output does not match schema',
          details: schemaValidation.error?.details,
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
      }

      final meta = <String, dynamic>{
        'provider': id,
        'binary_path': binaryPath,
        'attempt_count': attempts.length,
        'execution_timeout_ms': executionTimeout.inMilliseconds,
        'output_source': rawOutput.source,
        'output_bytes': rawOutput.byteLength,
        'attempts': attempts.map((final run) => run.toSummary()).toList(),
        if (rawOutput.sessionId != null)
          'cursor_session_id': rawOutput.sessionId,
      };
      if (request.metadata.isNotEmpty) {
        meta['request_metadata'] = request.metadata;
      }

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          output: normalizedOutput is Map<String, dynamic>
              ? normalizedOutput
              : parsed.data!,
          rawOutput: normalizedAssistantText,
          warnings: warnings,
          meta: meta,
        ),
        warnings: warnings,
        meta: meta,
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'cursor_exec_failed',
        message: 'Failed to execute cursor-agent',
        details: error.toString(),
      );
    }
  }

  String? _resolveModel(final InferenceRequest request) {
    final fromMeta = _stringFromMeta(
      request.metadata,
      'inferenceModel',
      'cursorAgentModel',
    );
    return _normalizeConfigValue(fromMeta) ??
        _normalizeConfigValue(defaultModel);
  }

  static String? _stringFromMeta(
    final Map<String, dynamic> meta,
    final String primaryKey,
    final String fallbackKey,
  ) {
    final primary = meta[primaryKey];
    if (primary != null) return '$primary'.trim();
    final fallback = meta[fallbackKey];
    if (fallback != null) return '$fallback'.trim();
    return null;
  }

  static String? _normalizeConfigValue(final String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<_ExecRunResult> _runExec({
    required final String binaryPath,
    required final InferenceRequest request,
  }) async {
    final model = _resolveModel(request);
    final args = <String>[
      '--print',
      '--output-format',
      'json',
      '--trust',
      '--workspace',
      request.workingDirectory,
      if (_hasText(model)) ...<String>['--model', model!],
      ...extraExecArgs,
      request.prompt,
    ];

    final startedAt = DateTime.now();
    final process = await Process.start(
      binaryPath,
      args,
      workingDirectory: request.workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    try {
      final exitCode = await process.exitCode.timeout(executionTimeout);
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      return _ExecRunResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        args: args,
        duration: DateTime.now().difference(startedAt),
      );
    } on TimeoutException {
      process.kill();
      await Future<void>.delayed(killGracePeriod);
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        // best-effort forced termination
      }

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -1,
      );
      final stdout = await stdoutFuture.timeout(
        const Duration(seconds: 1),
        onTimeout: () => '',
      );
      final stderr = await stderrFuture.timeout(
        const Duration(seconds: 1),
        onTimeout: () => '',
      );
      return _ExecRunResult(
        exitCode: exitCode == 0 ? -1 : exitCode,
        stdout: stdout,
        stderr: stderr,
        args: args,
        timedOut: true,
        duration: DateTime.now().difference(startedAt),
      );
    }
  }

  InferenceResult<_RawOutput> _readRawOutput({required final String stdout}) {
    final stdoutBytes = utf8.encode(stdout).length;
    if (stdoutBytes > maxOutputBytes) {
      return InferenceResult<_RawOutput>.fail(
        code: 'cursor_output_too_large',
        message: 'cursor-agent stdout output exceeded maxOutputBytes limit',
        details: <String, dynamic>{
          'output_bytes': stdoutBytes,
          'max_output_bytes': maxOutputBytes,
          'source': 'stdout',
        },
      );
    }

    if (stdout.trim().isEmpty) {
      return InferenceResult<_RawOutput>.fail(
        code: 'cursor_output_empty',
        message: 'cursor-agent produced no output',
        details: <String, dynamic>{'source': 'stdout'},
      );
    }

    final envelopeResult = _parseEnvelope(stdout);
    if (!envelopeResult.success || envelopeResult.data == null) {
      return InferenceResult<_RawOutput>.fail(
        code: envelopeResult.error?.code ?? 'cursor_output_invalid',
        message:
            envelopeResult.error?.message ??
            'cursor-agent output was not a valid JSON envelope',
        details: envelopeResult.error?.details,
      );
    }

    final envelope = envelopeResult.data!;
    final assistantText = envelope.result.trim();
    if (assistantText.isEmpty) {
      return InferenceResult<_RawOutput>.fail(
        code: 'cursor_output_empty',
        message: 'cursor-agent result payload is empty',
        details: <String, dynamic>{'source': 'stdout'},
      );
    }

    if (envelope.isError || envelope.subtype == 'error') {
      return InferenceResult<_RawOutput>.fail(
        code: 'cursor_output_invalid',
        message: 'cursor-agent returned an error envelope',
        details: <String, dynamic>{
          'type': envelope.type,
          'subtype': envelope.subtype,
          'result': _truncate(envelope.result),
        },
      );
    }

    return InferenceResult<_RawOutput>.ok(
      _RawOutput(
        assistantText: assistantText,
        source: 'stdout',
        byteLength: utf8.encode(assistantText).length,
        sessionId: envelope.sessionId,
      ),
    );
  }

  InferenceResult<_CursorEnvelope> _parseEnvelope(final String stdout) {
    final parsed = parseStrictJsonObject(stdout);
    if (parsed.success && parsed.data != null) {
      return _decodeEnvelope(parsed.data!);
    }

    final nonEmptyLines = LineSplitter.split(stdout)
        .map((final line) => line.trim())
        .where((final line) => line.isNotEmpty)
        .toList(growable: false);
    if (nonEmptyLines.isEmpty) {
      return InferenceResult<_CursorEnvelope>.fail(
        code: 'cursor_output_empty',
        message: 'cursor-agent produced no output lines',
      );
    }

    final lastLineParsed = parseStrictJsonObject(nonEmptyLines.last);
    if (!lastLineParsed.success || lastLineParsed.data == null) {
      return InferenceResult<_CursorEnvelope>.fail(
        code: 'cursor_output_invalid',
        message: 'cursor-agent output did not contain a valid JSON object',
        details: parsed.error?.details ?? _truncate(stdout),
      );
    }

    return _decodeEnvelope(lastLineParsed.data!);
  }

  InferenceResult<_CursorEnvelope> _decodeEnvelope(
    final Map<String, dynamic> json,
  ) {
    final type = json['type'];
    final result = json['result'];
    if (type is! String || result is! String) {
      return InferenceResult<_CursorEnvelope>.fail(
        code: 'cursor_output_invalid',
        message: 'cursor-agent JSON envelope is missing required fields',
        details: <String, dynamic>{
          'type': type,
          'result_type': result.runtimeType.toString(),
        },
      );
    }

    return InferenceResult<_CursorEnvelope>.ok(
      _CursorEnvelope(
        type: type,
        subtype: json['subtype'] as String?,
        isError: json['is_error'] == true,
        result: result,
        sessionId: json['session_id'] as String?,
      ),
    );
  }

  bool _isTransientFailure(final _ExecRunResult result) {
    if (result.timedOut) {
      return true;
    }
    final normalized = '${result.stderr}\n${result.stdout}'.toLowerCase();
    return normalized.contains('temporary failure') ||
        normalized.contains('temporarily unavailable') ||
        normalized.contains('connection reset') ||
        normalized.contains('network is unreachable') ||
        normalized.contains('rate limit') ||
        normalized.contains('resource busy') ||
        normalized.contains('econnreset') ||
        normalized.contains('etimedout');
  }

  bool _isAuthFailure(final _ExecRunResult result) {
    final normalized = '${result.stderr}\n${result.stdout}'.toLowerCase();
    return normalized.contains('401 unauthorized') ||
        normalized.contains('status: 401') ||
        normalized.contains('status 401') ||
        normalized.contains('invalid_api_key') ||
        normalized.contains('invalid api key') ||
        normalized.contains('authentication failed') ||
        normalized.contains('not logged in') ||
        normalized.contains('no credentials') ||
        normalized.contains('api key required') ||
        normalized.contains('login required') ||
        normalized.contains('unauthorized');
  }

  Map<String, dynamic> _buildFailureDetails({
    required final _ExecRunResult result,
    required final List<_ExecRunResult> attempts,
    required final bool authFailure,
  }) {
    final stderr = result.stderr.trim();
    final stdout = result.stdout.trim();
    return <String, dynamic>{
      'timed_out': result.timedOut,
      'exit_code': result.exitCode,
      'auth_failure': authFailure,
      if (stderr.isNotEmpty) 'stderr': _truncate(stderr),
      if (stdout.isNotEmpty) 'stdout': _truncate(stdout),
      if (authFailure)
        'remediation': <String>[
          'Provide CURSOR_API_KEY to cursor-agent.',
          'Or run cursor-agent login before running inference.',
        ],
      'attempts': attempts.map((final run) => run.toSummary()).toList(),
    };
  }

  String _truncate(final String value, {final int max = 2000}) {
    if (value.length <= max) {
      return value;
    }
    final headLength = max ~/ 2;
    final tailLength = max - headLength;
    final head = value.substring(0, headLength);
    final tail = value.substring(value.length - tailLength);
    return '$head...[truncated ${value.length - max} chars]...$tail';
  }

  String _normalizeAssistantText(final String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final directParse = parseStrictJsonObject(trimmed);
    if (directParse.success) {
      return trimmed;
    }

    final fencedJson = _extractFencedJsonObject(trimmed);
    if (fencedJson != null) {
      return fencedJson;
    }

    final embeddedJson = _extractEmbeddedJsonObject(trimmed);
    if (embeddedJson != null) {
      return embeddedJson;
    }

    return trimmed;
  }

  String? _extractFencedJsonObject(final String value) {
    final fencePattern = RegExp(
      r'```(?:json|javascript|js)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    );
    for (final match in fencePattern.allMatches(value)) {
      final candidate = match.group(1)?.trim();
      if (!_hasText(candidate)) {
        continue;
      }
      final parsed = parseStrictJsonObject(candidate!);
      if (parsed.success) {
        return candidate;
      }
    }
    return null;
  }

  String? _extractEmbeddedJsonObject(final String value) {
    String? lastValid;
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaping = false;

    for (var index = 0; index < value.length; index++) {
      final char = value[index];

      if (escaping) {
        escaping = false;
        continue;
      }

      if (char == r'\') {
        if (inString) {
          escaping = true;
        }
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (inString) {
        continue;
      }

      if (char == '{') {
        if (depth == 0) {
          start = index;
        }
        depth++;
        continue;
      }

      if (char == '}') {
        if (depth == 0) {
          continue;
        }
        depth--;
        if (depth == 0 && start >= 0) {
          final candidate = value.substring(start, index + 1).trim();
          final parsed = parseStrictJsonObject(candidate);
          if (parsed.success) {
            lastValid = candidate;
          }
          start = -1;
        }
      }
    }

    return lastValid;
  }

  Object? _normalizeForSchema(
    final Object? value,
    final Map<String, dynamic> schema,
  ) {
    final rawType = schema['type'];
    return switch (rawType) {
      'object' => _normalizeObjectForSchema(value, schema),
      'array' => _normalizeArrayForSchema(value, schema),
      'string' => _normalizeStringForSchema(value),
      _ => value,
    };
  }

  Object? _normalizeObjectForSchema(
    final Object? value,
    final Map<String, dynamic> schema,
  ) {
    if (value is! Map) {
      return value;
    }

    final normalized = <String, dynamic>{};
    final source = value.map(
      (final key, final nestedValue) => MapEntry('$key', nestedValue),
    );
    final properties = schema['properties'];
    final propertySchemas = properties is Map<String, dynamic>
        ? properties
        : const <String, dynamic>{};

    for (final entry in source.entries) {
      final propertySchema = propertySchemas[entry.key];
      if (propertySchema is Map<String, dynamic>) {
        normalized[entry.key] = _normalizeForSchema(
          entry.value,
          propertySchema,
        );
      } else {
        normalized[entry.key] = entry.value;
      }
    }

    return normalized;
  }

  Object? _normalizeArrayForSchema(
    final Object? value,
    final Map<String, dynamic> schema,
  ) {
    final itemSchema = schema['items'];
    final normalizedItemSchema = itemSchema is Map<String, dynamic>
        ? itemSchema
        : null;

    if (value is List) {
      if (normalizedItemSchema == null) {
        return value;
      }
      return value
          .map((final item) => _normalizeForSchema(item, normalizedItemSchema))
          .toList(growable: false);
    }

    if (value == null) {
      return value;
    }

    if (normalizedItemSchema == null) {
      return <Object?>[value];
    }

    return <Object?>[_normalizeForSchema(value, normalizedItemSchema)];
  }

  Object? _normalizeStringForSchema(final Object? value) {
    if (value == null || value is String) {
      return value;
    }
    if (value is List) {
      final flattened = value
          .map((final item) => _normalizeStringForSchema(item))
          .whereType<String>()
          .map((final item) => item.trim())
          .where((final item) => item.isNotEmpty)
          .toList(growable: false);
      if (flattened.isNotEmpty) {
        return flattened.join('\n');
      }
      return jsonEncode(value);
    }
    if (value is Map) {
      for (final key in const <String>['text', 'value', 'message', 'summary']) {
        final nested = value[key];
        final normalized = _normalizeStringForSchema(nested);
        if (normalized is String && normalized.trim().isNotEmpty) {
          return normalized;
        }
      }
      return jsonEncode(value);
    }
    return value;
  }

  bool _hasText(final String? value) =>
      value != null && value.trim().isNotEmpty;

  String? _resolveBinaryPath() {
    if (binaryName.contains(Platform.pathSeparator)) {
      return File(binaryName).existsSync() ? binaryName : null;
    }

    final activeEnvironment = environment ?? Platform.environment;
    final pathEnv = activeEnvironment['PATH'];
    if (pathEnv == null || pathEnv.isEmpty) {
      return null;
    }

    final pathSegments = pathEnv
        .split(Platform.isWindows ? ';' : ':')
        .where((final segment) => segment.isNotEmpty);

    for (final segment in pathSegments) {
      final candidate = p.join(segment, binaryName);
      final file = File(candidate);
      if (file.existsSync()) {
        return file.path;
      }
      if (Platform.isWindows) {
        for (final suffix in const <String>['.exe', '.cmd']) {
          final withSuffix = File('$candidate$suffix');
          if (withSuffix.existsSync()) {
            return withSuffix.path;
          }
        }
      }
    }

    return null;
  }
}

final class _ExecRunResult {
  const _ExecRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.args,
    required this.duration,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> args;
  final Duration duration;
  final bool timedOut;

  Map<String, dynamic> toSummary() => <String, dynamic>{
    'exit_code': exitCode,
    'timed_out': timedOut,
    'duration_ms': duration.inMilliseconds,
    'args': args.take(args.length - 1).toList(),
  };
}

final class _RawOutput {
  const _RawOutput({
    required this.assistantText,
    required this.source,
    required this.byteLength,
    this.sessionId,
  });

  final String assistantText;
  final String source;
  final int byteLength;
  final String? sessionId;
}

final class _CursorEnvelope {
  const _CursorEnvelope({
    required this.type,
    required this.result,
    required this.isError,
    this.subtype,
    this.sessionId,
  });

  final String type;
  final String? subtype;
  final bool isError;
  final String result;
  final String? sessionId;
}
