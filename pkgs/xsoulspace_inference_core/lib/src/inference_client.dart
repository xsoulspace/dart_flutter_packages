import '../xsoulspace_inference_core.dart';

export 'structured_output/structured_output.dart';
export 'tools/tool_contracts.dart';
export 'tools/tool_registry.dart';

abstract interface class InferenceClient {
  String get id;

  bool get isAvailable;

  Set<InferenceTask> get supportedTasks;

  /// Refreshes provider availability state and returns latest value.
  Future<bool> refreshAvailability();

  /// Loads model into CPU / GPU if possible.
  Future<void> load();

  /// Clears provider availability caches (if any).
  void resetAvailabilityCache();

  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  });
}
