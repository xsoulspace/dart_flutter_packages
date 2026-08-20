import 'dart:developer';

import '../inference_client.dart';
import '../models/inference_models.dart';
import 'structured_output/structured_output.dart';
import 'tool_call_parser.dart';

export 'structured_output/structured_output.dart';
export 'tool_call_parser.dart';

/// Any ML model
class Model {
  const Model({
    this.id = ModelId.empty,
    this.name = DefaultModelNames.appleFoundation,
  });
  static const empty = Model();
  final ModelId id;
  final ModelName name;
}

/// name of model
///
/// prefer to use deinitive enumeration like:
/// ```dart
/// enum ModelNames implements ModelName{
///
/// }
/// ```
abstract class ModelName implements Enum {}

enum DefaultModelNames implements ModelName { appleFoundation }

/// generated uuid
extension type const ModelId(String value) {
  //TODO(arenukvern): add uuid
  factory ModelId.create() => ModelId('${DateTime.now()}');
  static const empty = ModelId('');
}

/// organized and contiuos information
/// about agent goals, plans, history etc..
class ModelContextWindow {
  const ModelContextWindow();
  static const empty = ModelContextWindow();
}

typedef InferenceClientsBuilders = Map<ModelName, InferenceClientBuilder>;
typedef InferenceClientBuilder = InferenceClient Function();

/// the chooser of models
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
  Map<ModelId, ModelRuntime> runtimes;

  Future<ModelRuntime> waitAndGetRuntimeModel(Model model) async {
    final runtime = runtimes[model.id] ??= await initRuntime(model);

    return runtime;
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

/// 1 instance [ModelRuntime] holds:
/// - 1 only ML/LM [Model] and its [ModelContextWindow]
/// - organized and continuous information
/// about model goals, plans, history etc..
class ModelRuntime {
  ModelRuntime({
    required this.model,
    required this.client,
    this.context = ModelContextWindow.empty,
  });
  final Model model;
  final ModelContextWindow context;
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
  }) async {
    final response = await client.infer(
      InferenceRequest.structured(
        outputSchema: outputSchema,
        workingDirectory: '/tmp',
        prompt: prompt,
        systemPrompt: systemPrompt,
        task: task,
        contextFragments: contextFragments,
        metadata: {},
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
    final output = data?.output;
    if (output == null || output.isEmpty) {
      log('output is empty: $output');
    }
    return output ?? {};
  }
}

extension type const AgentId(String value) {
  //TODO(arenukvern): add uuid
  factory AgentId.create() => AgentId('${DateTime.now()}');
  static const empty = AgentId('');
}
