import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class CodexExecInferenceClient implements InferenceClient {
  CodexExecInferenceClient({
    this.binaryName = 'codex',
    this.environment,
    this.sandbox = 'workspace-write',
    this.primaryAutoArgs = const <String>['--full-auto'],
    this.fallbackAutoArgs = const <String>['-a', 'on-failure'],
    this.extraExecArgs = const <String>[],
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
  final String sandbox;
  final List<String> primaryAutoArgs;
  final List<String> fallbackAutoArgs;
  final List<String> extraExecArgs;
  final Duration executionTimeout;
  final int maxOutputBytes;
  final int maxAttempts;
  final int maxTimeoutRetries;
  final int maxTransientRetries;
  final Duration killGracePeriod;

  @override
  String get id => 'codex_exec';

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
    // No availability cache for codex binary resolution.
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
        message: 'codex binary not found in PATH',
      );
    }

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp(
        'xsoulspace_codex_schema_',
      );
      final schemaPath = p.join(tempDir.path, 'schema.json');
      final outputPath = p.join(tempDir.path, 'last_message.json');
      final warnings = <String>[];
      var autoArgs = primaryAutoArgs;
      var fallbackUsed = false;
      var timeoutRetriesLeft = maxTimeoutRetries;
      var transientRetriesLeft = maxTransientRetries;
      final attempts = <_ExecRunResult>[];

      await File(schemaPath).writeAsString(jsonEncode(request.outputSchema));

      while (attempts.length < maxAttempts) {
        final result = await _runExec(
          binaryPath: binaryPath,
          request: request,
          schemaPath: schemaPath,
          outputPath: outputPath,
          autoArgs: autoArgs,
        );
        attempts.add(result);

        if (result.exitCode == 0 && !result.timedOut) {
          break;
        }

        if (!fallbackUsed &&
            fallbackAutoArgs.isNotEmpty &&
            _shouldRetryLegacy(result.stderr)) {
          fallbackUsed = true;
          autoArgs = fallbackAutoArgs;
          warnings.add('Fallback auto-args used for legacy codex CLI flags.');
          continue;
        }

        if (result.timedOut && timeoutRetriesLeft > 0) {
          timeoutRetriesLeft--;
          warnings.add('Retrying codex exec after timeout.');
          continue;
        }

        if (_isTransientFailure(result) && transientRetriesLeft > 0) {
          transientRetriesLeft--;
          warnings.add('Retrying codex exec after transient process failure.');
          continue;
        }

        break;
      }

      if (attempts.isEmpty) {
        return InferenceResult<InferenceResponse>.fail(
          code: 'codex_exec_failed',
          message: 'codex exec was not attempted',
        );
      }

      final result = attempts.last;
      if (result.exitCode != 0) {
        final authFailure = _isAuthFailure(result);
        final code = result.timedOut
            ? 'codex_exec_timeout'
            : authFailure
            ? 'codex_auth_failed'
            : 'codex_exec_failed';
        final message = result.timedOut
            ? 'codex exec timed out after ${executionTimeout.inMilliseconds}ms'
            : authFailure
            ? 'codex exec authentication failed; use CODEX_API_KEY or codex login --with-api-key'
            : 'codex exec failed with exit code ${result.exitCode}';
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

      final rawOutputResult = await _readRawOutput(
        outputPath: outputPath,
        stdoutFallback: result.stdout,
      );
      if (!rawOutputResult.success || rawOutputResult.data == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: rawOutputResult.error?.code ?? 'codex_output_unavailable',
          message:
              rawOutputResult.error?.message ?? 'Failed to read codex output',
          details: rawOutputResult.error?.details,
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
      }
      final rawOutput = rawOutputResult.data!.raw;

      final parsed = parseStrictJsonObject(rawOutput);
      if (!parsed.success || parsed.data == null) {
        return InferenceResult<InferenceResponse>.fail(
          code: parsed.error?.code ?? 'codex_parse_failed',
          message:
              parsed.error?.message ??
              'Failed to parse structured output from codex',
          details: parsed.error?.details ?? _truncate(rawOutput),
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
      }

      final schemaValidation = validateJsonAgainstSchema(
        value: parsed.data!,
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
        'fallback_used': fallbackUsed,
        'execution_timeout_ms': executionTimeout.inMilliseconds,
        'output_source': rawOutputResult.data!.source,
        'output_bytes': rawOutputResult.data!.byteLength,
        'attempts': attempts.map((final run) => run.toSummary()).toList(),
      };
      if (request.metadata.isNotEmpty) {
        meta['request_metadata'] = request.metadata;
      }

      return InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          output: parsed.data!,
          rawOutput: rawOutput,
          warnings: warnings,
          meta: meta,
        ),
        warnings: warnings,
        meta: meta,
      );
    } on FileSystemException catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'codex_io_failed',
        message: 'Failed to write schema/output files for codex exec',
        details: error.toString(),
      );
    } catch (error) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'codex_exec_failed',
        message: 'Failed to execute codex',
        details: error.toString(),
      );
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // best-effort cleanup
        }
      }
    }
  }

  Future<_ExecRunResult> _runExec({
    required final String binaryPath,
    required final InferenceRequest request,
    required final String schemaPath,
    required final String outputPath,
    required final List<String> autoArgs,
  }) async {
    final args = <String>[
      'exec',
      '--sandbox',
      sandbox,
      ...autoArgs,
      '--output-schema',
      schemaPath,
      '--output-last-message',
      outputPath,
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
        autoArgs: autoArgs,
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
        autoArgs: autoArgs,
        timedOut: true,
        duration: DateTime.now().difference(startedAt),
      );
    }
  }

  Future<InferenceResult<_RawOutput>> _readRawOutput({
    required final String outputPath,
    required final String stdoutFallback,
  }) async {
    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final outputBytes = await outputFile.length();
      if (outputBytes > maxOutputBytes) {
        return InferenceResult<_RawOutput>.fail(
          code: 'codex_output_too_large',
          message: 'codex output file exceeded maxOutputBytes limit',
          details: <String, dynamic>{
            'output_bytes': outputBytes,
            'max_output_bytes': maxOutputBytes,
            'source': 'file',
          },
        );
      }

      final raw = await outputFile.readAsString();
      if (raw.trim().isEmpty) {
        return InferenceResult<_RawOutput>.fail(
          code: 'codex_output_empty',
          message: 'codex output file is empty',
          details: <String, dynamic>{'source': 'file'},
        );
      }

      return InferenceResult<_RawOutput>.ok(
        _RawOutput(raw: raw, source: 'file', byteLength: outputBytes),
      );
    }

    final stdoutBytes = utf8.encode(stdoutFallback).length;
    if (stdoutBytes > maxOutputBytes) {
      return InferenceResult<_RawOutput>.fail(
        code: 'codex_output_too_large',
        message: 'codex stdout output exceeded maxOutputBytes limit',
        details: <String, dynamic>{
          'output_bytes': stdoutBytes,
          'max_output_bytes': maxOutputBytes,
          'source': 'stdout',
        },
      );
    }

    if (stdoutFallback.trim().isEmpty) {
      return InferenceResult<_RawOutput>.fail(
        code: 'codex_output_empty',
        message: 'codex produced no output',
        details: <String, dynamic>{'source': 'stdout'},
      );
    }

    return InferenceResult<_RawOutput>.ok(
      _RawOutput(
        raw: stdoutFallback,
        source: 'stdout',
        byteLength: stdoutBytes,
      ),
    );
  }

  bool _shouldRetryLegacy(final String stderr) {
    final normalized = stderr.toLowerCase();
    return normalized.contains('unexpected argument') ||
        normalized.contains('found argument') ||
        normalized.contains('unrecognized option');
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
        normalized.contains('resource busy');
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
        normalized.contains('no credentials');
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
          'Provide CODEX_API_KEY to codex exec.',
          'Or run codex login --with-api-key before running inference.',
        ],
      'attempts': attempts.map((final run) => run.toSummary()).toList(),
    };
  }

  String _truncate(final String value, {final int max = 2000}) {
    if (value.length <= max) {
      return value;
    }
    return '${value.substring(0, max)}...[truncated ${value.length - max} chars]';
  }

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
    required this.autoArgs,
    required this.duration,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> autoArgs;
  final Duration duration;
  final bool timedOut;

  Map<String, dynamic> toSummary() => <String, dynamic>{
    'exit_code': exitCode,
    'timed_out': timedOut,
    'duration_ms': duration.inMilliseconds,
    'auto_args': autoArgs,
  };
}

final class _RawOutput {
  const _RawOutput({
    required this.raw,
    required this.source,
    required this.byteLength,
  });

  final String raw;
  final String source;
  final int byteLength;
}
