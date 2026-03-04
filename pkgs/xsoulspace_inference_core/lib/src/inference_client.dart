import 'inference_models.dart';
import 'inference_result.dart';

abstract interface class InferenceClient {
  String get id;

  bool get isAvailable;

  Future<InferenceResult<InferenceResponse>> infer(InferenceRequest request);
}
