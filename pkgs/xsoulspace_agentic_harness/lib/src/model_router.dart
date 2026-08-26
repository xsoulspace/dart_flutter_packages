import 'dart:async';
import 'dart:developer';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
export 'package:xsoulspace_inference_core/src/models/model_catalog.dart'
    show DefaultModelNames, Model, ModelId, ModelName;

import 'tools/tools.dart';



/// Collision-free unique id generation.
///
/// Timestamp alone collides when ids are created within the same microsecond
/// (e.g. spawning N actors in a loop), so a process-wide monotonic counter is
/// mixed in. Deterministic — no external dependency, works on all platforms.
int _idCounter = 0;
String nextUniqueId(String prefix) {
  final count = _idCounter++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$count';
}

/// Lazily-built inference clients keyed by provider model name.
typedef InferenceClientsBuilders = Map<ModelName, InferenceClient Function()>;

class ModelRouter {
  /// it is important to pass not const empty maps,
  /// because directly mutable
  ModelRouter({
    InferenceClientsBuilders? inferenceClientsBuilders,
    Map<ModelId, Model>? models,
    Map<ModelId, ModelRuntime>? runtimes,
  }) : inferenceClientsBuilders = inferenceClientsBuilders ?? {},
       models = models ?? {},
       runtimes = runtimes ?? {};

  final InferenceClientsBuilders inferenceClientsBuilders;
  Map<ModelId, Model> models;

  /// Loaded runtimes, keyed by model id.
  final Map<ModelId, ModelRuntime> runtimes;

  /// In-flight runtime initializations — concurrent requests for the same
  /// unloaded model share one [initRuntime] call instead of double-loading
  /// the client.
  final Map<ModelId, Future<ModelRuntime>> _pendingRuntimes = {};

  Future<ModelRuntime> waitAndGetRuntimeModel(Model model) {
    final existing = runtimes[model.id];
    if (existing != null) return Future.value(existing);
    return _pendingRuntimes.putIfAbsent(model.id, () async {
      try {
        final runtime = await initRuntime(model);
        runtimes[model.id] = runtime;
        return runtime;
      } finally {
        _pendingRuntimes.remove(model.id);
      }
    });
  }

  Future<ModelRuntime> initRuntime(Model model) async {
    final client = inferenceClientsBuilders[model.name]?.call();
    if (client == null) {
      throw ArgumentError.notNull(
        'inference client is not created for ${model.name}',
      );
    }

    final runtime = await ModelRuntime.initFromInference(
      model: model,
      client: client,
    );

    return runtime;
  }
}

/// A loaded, callable model bound to its inference client.
class ModelRuntime {
  ModelRuntime({required this.model, required this.client});
  final Model model;
  final InferenceClient client;
  bool get isRunning => client.isAvailable;

  static Future<ModelRuntime> initFromInference({
    required Model model,
    required InferenceClient client,
  }) async {
    final runtime = ModelRuntime(model: model, client: client);
    await runtime.load();
    return runtime;
  }

  Future<void> load() async {
    await client.load();
    await client.refreshAvailability();
  }

  Future<InferenceResponse?> generate({
    required String prompt,
    required List<Object> contextFragments,
    required String systemPrompt,
    required SchemaBundle outputSchema,
    required ToolRegistry? toolRegistry,
    required InferenceTask task,
    void Function(String delta)? onDelta,
  }) async {
    // Streaming path: only for plain-text tasks where the client supports it.
    if (onDelta != null &&
        outputSchema.isEmpty &&
        toolRegistry == null &&
        client.supportsStructuredTextStreaming) {
      final session = await client.streamStructuredText(
        InferenceRequest.structured(
          outputSchema: SchemaBundle.empty,
          prompt: prompt,
          systemPrompt: systemPrompt,
          task: task,
          contextFragments: contextFragments,
          metadata: const {},
        ),
      );
      final buffer = StringBuffer();
      // Drain events and result concurrently; await BOTH so the buffer is
      // complete before we return (result can complete before the last
      // delta event is delivered).
      final draining = session.events.forEach((event) {
        final delta = event.textDelta;
        if (delta != null && delta.isNotEmpty) {
          buffer.write(delta);
          onDelta(delta);
        }
      });
      final results = await (session.result, draining).wait;
      final result = results.$1;
      if (!result.success || result.data == null) {
        log('stream failed: ${result.error?.code}');
        return null;
      }
      // Prefer the accumulated buffer (complete text); fall back to rawOutput.
      final data = result.data!;
      final streamed = buffer.toString();
      return InferenceResponse(
        structuredOutput: data.structuredOutput,
        rawOutput: streamed.isNotEmpty ? streamed : data.rawOutput,
        meta: data.meta,
      );
    }

    final response = await client.infer(
      InferenceRequest.structured(
        outputSchema: outputSchema,
        prompt: prompt,
        systemPrompt: systemPrompt,
        task: task,
        contextFragments: contextFragments,
        metadata: const {},
      ),
      // inline tools should be included to systemprompt or similar
      toolRegistry: toolRegistry,
    );
    final data = response.data;
    log('rawOutput is ${data?.rawOutput}');
    return data;
  }

  Future<Map<String, dynamic>> generateStructuredText({
    required String prompt,
    required List<Object> contextFragments,
    required String systemPrompt,
    required SchemaBundle outputSchema,
    required ToolRegistry toolRegistry,
  }) async {
    final data = await generate(
      outputSchema: outputSchema,
      toolRegistry: toolRegistry,
      prompt: prompt,
      systemPrompt: systemPrompt,
      task: InferenceTask.nativelyStructuredText,
      contextFragments: contextFragments,
    );
    final output = data?.structuredOutput;
    if (output == null || output.isEmpty) {
      log('output is empty: $output');
    }
    return output ?? {};
  }
}

extension type const AgentId(String value) {
  factory AgentId.create() => AgentId(nextUniqueId('agent'));
  static const empty = AgentId('');
}
