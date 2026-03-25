import 'inference_models.dart';
import 'inference_result.dart';

abstract interface class InferenceClient {
  String get id;

  bool get isAvailable;

  Set<InferenceTask> get supportedTasks;

  /// Refreshes provider availability state and returns latest value.
  Future<bool> refreshAvailability();

  /// Clears provider availability caches (if any).
  void resetAvailabilityCache();

  Future<InferenceResult<InferenceResponse>> infer(InferenceRequest request);
}
