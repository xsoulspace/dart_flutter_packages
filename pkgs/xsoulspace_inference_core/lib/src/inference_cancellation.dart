import 'inference_client.dart';

/// Optional execution lifetime for a provider instance. Composition creates
/// separate instances for independently cancellable sessions. Shared model or
/// authentication resources do not imply shared logical cancellation.
abstract interface class CancellableInferenceClient implements InferenceClient {
  void cancelActive();
  Future<void> settleActive();
  void close();
}
