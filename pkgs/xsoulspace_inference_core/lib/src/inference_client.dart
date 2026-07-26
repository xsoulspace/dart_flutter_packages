import 'inference_result.dart';
import 'models/inference_models.dart';

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

  Future<InferenceResult<InferenceResponse>> infer(InferenceRequest request);
}
