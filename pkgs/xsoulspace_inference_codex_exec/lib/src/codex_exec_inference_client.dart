import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class CodexExecInferenceClient
    implements InferenceClient, StructuredTextStreamingInferenceClient {
  CodexExecInferenceClient({
    this.binaryName = 'codex',
    this.environment,
    this.sandbox = 'workspace-write',
    this.primaryAutoArgs = const <String>['--full-auto'],
    this.fallbackAutoArgs = const <String>['-a', 'on-failure'],
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
  final String sandbox;
  final List<String> primaryAutoArgs;
  final List<String> fallbackAutoArgs;
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
  ) => _runInference(request);

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    final InferenceRequest request,
  ) async {
    final session = _CodexStructuredTextStreamSession();
    session.start(
      () => _runInference(
        request,
        onEvent: session.emit,
        executionControl: session.executionControl,
      ),
    );
    return session;
  }

  Future<InferenceResult<InferenceResponse>> _runInference(
    final InferenceRequest request, {
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final _ExecutionControl? executionControl,
  }) async {
    final preflightFailure = _validateRequest(request);
    if (preflightFailure != null) {
      _emitFailure(
        onEvent,
        preflightFailure,
        attempt: 1,
        lifecycleState: InferenceStructuredTextLifecycleState.failed,
      );
      return preflightFailure;
    }

    final binaryPath = _resolveBinaryPath()!;
    _emitLifecycle(
      onEvent,
      InferenceStructuredTextLifecycleState.started,
      message: 'Starting codex exec stream.',
      attempt: 1,
      metadata: <String, dynamic>{'binary_path': binaryPath},
    );

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp(
        'xsoulspace_codex_schema_',
      );
      final schemaPath = p.join(tempDir.path, 'schema.json');
      final outputPath = p.join(tempDir.path, 'last_message.json');
      final warnings = <String>[];
      final attempts = <_ExecRunResult>[];
      var autoArgs = primaryAutoArgs;
      var fallbackUsed = false;
      var timeoutRetriesLeft = maxTimeoutRetries;
      var transientRetriesLeft = maxTransientRetries;

      await File(schemaPath).writeAsString(jsonEncode(request.outputSchema));

      while (attempts.length < maxAttempts) {
        final attempt = attempts.length + 1;
        if (executionControl?.canceled == true) {
          final canceledResult = InferenceResult<InferenceResponse>.fail(
            code: 'codex_exec_cancelled',
            message: 'codex exec stream was cancelled',
            meta: <String, dynamic>{'attempt_count': attempts.length},
          );
          _emitFailure(
            onEvent,
            canceledResult,
            attempt: attempt,
            lifecycleState: InferenceStructuredTextLifecycleState.failed,
          );
          return canceledResult;
        }

        _emitLifecycle(
          onEvent,
          InferenceStructuredTextLifecycleState.running,
          message: 'Running codex exec.',
          attempt: attempt,
          metadata: <String, dynamic>{'auto_args': autoArgs},
        );
        final result = await _runExec(
          binaryPath: binaryPath,
          request: request,
          schemaPath: schemaPath,
          outputPath: outputPath,
          autoArgs: autoArgs,
          attempt: attempt,
          onEvent: onEvent,
          executionControl: executionControl,
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
          const warning = 'Fallback auto-args used for legacy codex CLI flags.';
          warnings.add(warning);
          _emitWarning(onEvent, warning, attempt: attempt);
          _emitLifecycle(
            onEvent,
            InferenceStructuredTextLifecycleState.retrying,
            message: 'Retrying codex exec with fallback CLI flags.',
            attempt: attempt + 1,
          );
          continue;
        }

        if (result.timedOut && timeoutRetriesLeft > 0) {
          timeoutRetriesLeft--;
          const warning = 'Retrying codex exec after timeout.';
          warnings.add(warning);
          _emitWarning(onEvent, warning, attempt: attempt, isTransient: true);
          _emitLifecycle(
            onEvent,
            InferenceStructuredTextLifecycleState.retrying,
            message: 'Retrying codex exec after timeout.',
            attempt: attempt + 1,
          );
          continue;
        }

        if (_isTransientFailure(result) && transientRetriesLeft > 0) {
          transientRetriesLeft--;
          const warning =
              'Retrying codex exec after transient process failure.';
          warnings.add(warning);
          _emitWarning(onEvent, warning, attempt: attempt, isTransient: true);
          _emitLifecycle(
            onEvent,
            InferenceStructuredTextLifecycleState.retrying,
            message: 'Retrying codex exec after transient failure.',
            attempt: attempt + 1,
          );
          continue;
        }

        break;
      }

      if (attempts.isEmpty) {
        final result = InferenceResult<InferenceResponse>.fail(
          code: 'codex_exec_failed',
          message: 'codex exec was not attempted',
        );
        _emitFailure(
          onEvent,
          result,
          attempt: 1,
          lifecycleState: InferenceStructuredTextLifecycleState.failed,
        );
        return result;
      }

      final runResult = attempts.last;
      if (runResult.exitCode != 0) {
        final result = _buildExecFailureResult(
          result: runResult,
          attempts: attempts,
          warnings: warnings,
        );
        _emitFailure(
          onEvent,
          result,
          attempt: attempts.length,
          lifecycleState: runResult.timedOut
              ? InferenceStructuredTextLifecycleState.timedOut
              : InferenceStructuredTextLifecycleState.failed,
        );
        return result;
      }

      final rawOutputResult = await _readRawOutput(
        outputPath: outputPath,
        stdoutFallback: runResult.stdout,
      );
      if (!rawOutputResult.success || rawOutputResult.data == null) {
        final result = InferenceResult<InferenceResponse>.fail(
          code: rawOutputResult.error?.code ?? 'codex_output_unavailable',
          message:
              rawOutputResult.error?.message ?? 'Failed to read codex output',
          details: rawOutputResult.error?.details,
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
        _emitFailure(
          onEvent,
          result,
          attempt: attempts.length,
          lifecycleState: InferenceStructuredTextLifecycleState.failed,
        );
        return result;
      }

      final rawOutput = rawOutputResult.data!.raw;
      final parsed = parseStrictJsonObject(rawOutput);
      if (!parsed.success || parsed.data == null) {
        final result = InferenceResult<InferenceResponse>.fail(
          code: parsed.error?.code ?? 'codex_parse_failed',
          message:
              parsed.error?.message ??
              'Failed to parse structured output from codex',
          details: parsed.error?.details ?? _truncate(rawOutput),
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
        _emitFailure(
          onEvent,
          result,
          attempt: attempts.length,
          lifecycleState: InferenceStructuredTextLifecycleState.failed,
        );
        return result;
      }

      final schemaValidation = validateJsonAgainstSchema(
        value: parsed.data!,
        schema: request.outputSchema,
      );
      if (!schemaValidation.success) {
        final result = InferenceResult<InferenceResponse>.fail(
          code: schemaValidation.error?.code ?? 'schema_validation_failed',
          message:
              schemaValidation.error?.message ??
              'Inference output does not match schema',
          details: schemaValidation.error?.details,
          warnings: warnings,
          meta: <String, dynamic>{'attempt_count': attempts.length},
        );
        _emitFailure(
          onEvent,
          result,
          attempt: attempts.length,
          lifecycleState: InferenceStructuredTextLifecycleState.failed,
        );
        return result;
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
        if (_resolveModel(request) != null) 'model': _resolveModel(request),
        if (_resolveReasoningEffort(request) != null)
          'reasoning_effort': _resolveReasoningEffort(request),
      };
      if (request.metadata.isNotEmpty) {
        meta['request_metadata'] = request.metadata;
      }

      final result = InferenceResult<InferenceResponse>.ok(
        InferenceResponse(
          output: parsed.data!,
          rawOutput: rawOutput,
          warnings: warnings,
          meta: meta,
        ),
        warnings: warnings,
        meta: meta,
      );
      _emitLifecycle(
        onEvent,
        InferenceStructuredTextLifecycleState.completed,
        message: 'codex exec completed successfully.',
        attempt: attempts.length,
        metadata: <String, dynamic>{
          'output_source': rawOutputResult.data!.source,
          'output_bytes': rawOutputResult.data!.byteLength,
        },
      );
      _emitCompletion(onEvent, result, attempt: attempts.length);
      return result;
    } on FileSystemException catch (error) {
      final result = InferenceResult<InferenceResponse>.fail(
        code: 'codex_io_failed',
        message: 'Failed to write schema/output files for codex exec',
        details: error.toString(),
      );
      _emitFailure(
        onEvent,
        result,
        attempt: 1,
        lifecycleState: InferenceStructuredTextLifecycleState.failed,
      );
      return result;
    } catch (error) {
      final result = InferenceResult<InferenceResponse>.fail(
        code: 'codex_exec_failed',
        message: 'Failed to execute codex',
        details: error.toString(),
      );
      _emitFailure(
        onEvent,
        result,
        attempt: 1,
        lifecycleState: InferenceStructuredTextLifecycleState.failed,
      );
      return result;
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

  InferenceResult<InferenceResponse>? _validateRequest(
    final InferenceRequest request,
  ) {
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

    if (_resolveBinaryPath() == null) {
      return InferenceResult<InferenceResponse>.fail(
        code: 'engine_unavailable',
        message: 'codex binary not found in PATH',
      );
    }
    return null;
  }

  InferenceResult<InferenceResponse> _buildExecFailureResult({
    required final _ExecRunResult result,
    required final List<_ExecRunResult> attempts,
    required final List<String> warnings,
  }) {
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

  Future<_ExecRunResult> _runExec({
    required final String binaryPath,
    required final InferenceRequest request,
    required final String schemaPath,
    required final String outputPath,
    required final List<String> autoArgs,
    required final int attempt,
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final _ExecutionControl? executionControl,
  }) async {
    final skipGitRepoCheck = !Directory(
      p.join(request.workingDirectory, '.git'),
    ).existsSync();
    final model = _resolveModel(request);
    final reasoningEffort = _resolveReasoningEffort(request);
    final args = <String>[
      'exec',
      '--sandbox',
      sandbox,
      ...autoArgs,
      if (_hasText(model)) ...<String>['--model', model!],
      if (_hasText(reasoningEffort)) ...<String>[
        '-c',
        'reasoning.effort="$reasoningEffort"',
      ],
      '--ephemeral',
      if (skipGitRepoCheck) '--skip-git-repo-check',
      '--output-schema',
      schemaPath,
      '--output-last-message',
      outputPath,
      ...extraExecArgs,
      '-',
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
    executionControl?.attach(process);

    unawaited(() async {
      try {
        process.stdin.write(request.prompt);
        await process.stdin.flush();
      } on SocketException {
        // The child process can exit before consuming stdin; let the
        // normal exit-code path report the failure instead of crashing.
      } finally {
        try {
          await process.stdin.close();
        } on SocketException {
          // best-effort close
        }
      }
    }());

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    late final StreamSubscription<String> stdoutSub;
    late final StreamSubscription<String> stderrSub;

    void handleChunk(
      final InferenceStructuredTextRawChannel channel,
      final String chunk,
    ) {
      if (chunk.isEmpty) {
        return;
      }
      if (channel == InferenceStructuredTextRawChannel.stdout) {
        stdoutBuffer.write(chunk);
      } else {
        stderrBuffer.write(chunk);
      }
      _emitRaw(
        onEvent,
        channel,
        chunk,
        attempt: attempt,
        metadata: <String, dynamic>{'auto_args': autoArgs},
      );
      final trimmed = chunk.trim();
      if (trimmed.isNotEmpty) {
        if (channel == InferenceStructuredTextRawChannel.stdout) {
          _emitPartialOutput(onEvent, trimmed, attempt: attempt);
        } else {
          _emitProgress(
            onEvent,
            trimmed,
            attempt: attempt,
            metadata: const <String, dynamic>{'source': 'stderr'},
          );
        }
      }
    }

    stdoutSub = process.stdout
        .transform(utf8.decoder)
        .listen(
          (final chunk) =>
              handleChunk(InferenceStructuredTextRawChannel.stdout, chunk),
          onDone: () => stdoutDone.complete(),
          onError: (final Object error, final StackTrace stackTrace) {
            stdoutBuffer.write('$error');
            if (!stdoutDone.isCompleted) {
              stdoutDone.complete();
            }
          },
          cancelOnError: false,
        );
    stderrSub = process.stderr
        .transform(utf8.decoder)
        .listen(
          (final chunk) =>
              handleChunk(InferenceStructuredTextRawChannel.stderr, chunk),
          onDone: () => stderrDone.complete(),
          onError: (final Object error, final StackTrace stackTrace) {
            stderrBuffer.write('$error');
            if (!stderrDone.isCompleted) {
              stderrDone.complete();
            }
          },
          cancelOnError: false,
        );

    try {
      final exitCode = await process.exitCode.timeout(executionTimeout);
      await Future.wait(<Future<void>>[stdoutDone.future, stderrDone.future]);
      await stdoutSub.cancel();
      await stderrSub.cancel();
      return _ExecRunResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        autoArgs: autoArgs,
        duration: DateTime.now().difference(startedAt),
      );
    } on TimeoutException {
      _emitLifecycle(
        onEvent,
        InferenceStructuredTextLifecycleState.timedOut,
        message: 'codex exec timed out.',
        attempt: attempt,
      );
      await executionControl?.cancel();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -1,
      );
      await Future.wait(<Future<void>>[
        stdoutDone.future.timeout(const Duration(seconds: 1), onTimeout: () {}),
        stderrDone.future.timeout(const Duration(seconds: 1), onTimeout: () {}),
      ]);
      await stdoutSub.cancel();
      await stderrSub.cancel();
      return _ExecRunResult(
        exitCode: exitCode == 0 ? -1 : exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        autoArgs: autoArgs,
        timedOut: true,
        duration: DateTime.now().difference(startedAt),
      );
    } finally {
      executionControl?.detach(process);
    }
  }

  String? _resolveModel(final InferenceRequest request) {
    final metadataValue =
        request.metadata['inferenceModel'] ??
        request.metadata['codexExecModel'];
    final normalized = _normalizeConfigValue(
      metadataValue == null ? null : '$metadataValue',
    );
    return normalized ?? _normalizeConfigValue(defaultModel);
  }

  String? _resolveReasoningEffort(final InferenceRequest request) {
    final metadataValue =
        request.metadata['inferenceReasoningEffort'] ??
        request.metadata['codexExecReasoningEffort'];
    final normalized = _normalizeReasoningEffort(
      metadataValue == null ? null : '$metadataValue',
    );
    return normalized ?? _normalizeReasoningEffort(defaultReasoningEffort);
  }

  bool _hasText(final String? value) =>
      value != null && value.trim().isNotEmpty;

  String? _normalizeConfigValue(final String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? _normalizeReasoningEffort(final String? value) {
    final trimmed = _normalizeConfigValue(value)?.toLowerCase();
    return switch (trimmed) {
      null => null,
      'middle' => 'medium',
      _ => trimmed,
    };
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
          details: const <String, dynamic>{'source': 'file'},
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
        details: const <String, dynamic>{'source': 'stdout'},
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

  void _emitLifecycle(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final InferenceStructuredTextLifecycleState state, {
    required final String message,
    required final int attempt,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => _emitEvent(
    onEvent,
    InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.lifecycle,
      timestamp: DateTime.now().toUtc(),
      lifecycleState: state,
      message: message,
      attempt: attempt,
      metadata: metadata,
    ),
  );

  void _emitProgress(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final String message, {
    required final int attempt,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => _emitEvent(
    onEvent,
    InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.progress,
      timestamp: DateTime.now().toUtc(),
      message: message,
      attempt: attempt,
      metadata: metadata,
    ),
  );

  void _emitPartialOutput(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final String textDelta, {
    required final int attempt,
  }) => _emitEvent(
    onEvent,
    InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.partialOutput,
      timestamp: DateTime.now().toUtc(),
      textDelta: textDelta,
      attempt: attempt,
    ),
  );

  void _emitRaw(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final InferenceStructuredTextRawChannel channel,
    final String rawText, {
    required final int attempt,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => _emitEvent(
    onEvent,
    InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.raw,
      timestamp: DateTime.now().toUtc(),
      rawChannel: channel,
      rawText: rawText,
      attempt: attempt,
      metadata: metadata,
    ),
  );

  void _emitWarning(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final String message, {
    required final int attempt,
    final bool isTransient = false,
  }) => _emitEvent(
    onEvent,
    InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.warning,
      timestamp: DateTime.now().toUtc(),
      message: message,
      attempt: attempt,
      isTransient: isTransient,
    ),
  );

  void _emitFailure(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final InferenceResult<InferenceResponse> result, {
    required final int attempt,
    required final InferenceStructuredTextLifecycleState lifecycleState,
  }) {
    _emitLifecycle(
      onEvent,
      lifecycleState,
      message: result.error?.message ?? 'codex exec failed.',
      attempt: attempt,
    );
    _emitEvent(
      onEvent,
      InferenceStructuredTextStreamEvent(
        type: InferenceStructuredTextStreamEventType.error,
        timestamp: DateTime.now().toUtc(),
        message: result.error?.message,
        attempt: attempt,
        error: result.error,
        metadata: result.meta,
      ),
    );
    _emitCompletion(onEvent, result, attempt: attempt);
  }

  void _emitCompletion(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final InferenceResult<InferenceResponse> result, {
    required final int attempt,
  }) => _emitEvent(
    onEvent,
    InferenceStructuredTextStreamEvent(
      type: InferenceStructuredTextStreamEventType.completion,
      timestamp: DateTime.now().toUtc(),
      attempt: attempt,
      completion: InferenceStructuredTextCompletion(
        result: result,
        attemptCount: (result.meta['attempt_count'] as num?)?.toInt(),
      ),
      metadata: result.meta,
    ),
  );

  void _emitEvent(
    final void Function(InferenceStructuredTextStreamEvent event)? onEvent,
    final InferenceStructuredTextStreamEvent event,
  ) {
    if (onEvent == null) {
      return;
    }
    onEvent(event);
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
    final headLength = max ~/ 2;
    final tailLength = max - headLength;
    final head = value.substring(0, headLength);
    final tail = value.substring(value.length - tailLength);
    return '$head...[truncated ${value.length - max} chars]...$tail';
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

final class _ExecutionControl {
  Process? _process;
  bool _canceled = false;

  bool get canceled => _canceled;

  void attach(final Process process) {
    _process = process;
    if (_canceled) {
      _kill(process);
    }
  }

  void detach(final Process process) {
    if (identical(_process, process)) {
      _process = null;
    }
  }

  Future<void> cancel() async {
    _canceled = true;
    final process = _process;
    if (process == null) {
      return;
    }
    _kill(process);
  }

  void _kill(final Process process) {
    process.kill();
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      // best-effort forced termination
    }
  }
}

final class _CodexStructuredTextStreamSession
    implements InferenceStructuredTextStreamSession {
  final StreamController<InferenceStructuredTextStreamEvent> _controller =
      StreamController<InferenceStructuredTextStreamEvent>.broadcast(
        sync: true,
      );
  final Completer<InferenceResult<InferenceResponse>> _resultCompleter =
      Completer<InferenceResult<InferenceResponse>>();
  final _ExecutionControl executionControl = _ExecutionControl();
  bool _disposed = false;

  @override
  Stream<InferenceStructuredTextStreamEvent> get events => _controller.stream;

  @override
  Future<InferenceResult<InferenceResponse>> get result =>
      _resultCompleter.future;

  void emit(final InferenceStructuredTextStreamEvent event) {
    if (_disposed || _controller.isClosed) {
      return;
    }
    _controller.add(event);
  }

  void start(final Future<InferenceResult<InferenceResponse>> Function() run) {
    unawaited(() async {
      try {
        final resolved = await run();
        if (!_resultCompleter.isCompleted) {
          _resultCompleter.complete(resolved);
        }
      } catch (error) {
        if (!_resultCompleter.isCompleted) {
          _resultCompleter.complete(
            InferenceResult<InferenceResponse>.fail(
              code: 'codex_exec_failed',
              message: 'Failed to execute codex',
              details: '$error',
            ),
          );
        }
      } finally {
        await dispose();
      }
    }());
  }

  @override
  Future<void> cancel() => executionControl.cancel();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.complete(
        InferenceResult<InferenceResponse>.fail(
          code: 'codex_exec_cancelled',
          message: 'codex exec stream was cancelled',
        ),
      );
    }
    await _controller.close();
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
