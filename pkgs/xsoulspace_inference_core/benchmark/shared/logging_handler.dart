// ignore_for_file: lines_longer_than_80_chars

/// Shared observability decorators for benchmark bins.
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Logs every decision's tool calls, structured payload, and thrown errors to
/// stdout. Wrap the real backend handler; enable only under `--verbose` so
/// quiet runs pay nothing.
class LoggingHandler implements GenerationHandler {
  LoggingHandler(this.inner, {this.enabled = true});
  final GenerationHandler inner;
  final bool enabled;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    try {
      final response = await inner.generate(world, request);
      if (!enabled) return response;
      final names = response.toolCalls.map((t) => t.name.value).toList();
      stdout.writeln('[decision] toolCalls=$names error=${response.error}');
      if (names.isEmpty && response.structuredOutput.isNotEmpty) {
        stdout.writeln('[decision] structured=${response.structuredOutput}');
      }
      return response;
    } on Object catch (e) {
      stdout.writeln('[decision] THREW: $e');
      rethrow;
    }
  }
}
