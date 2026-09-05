export 'components.dart';
// The context-fragment protocol + wire codec moved to inference_core
// (ADR 0026) — they define core's `InferenceRequest.contextFragments`
// field and its canonical `messages` rendering; re-exported so existing
// harness consumers keep compiling.
export 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ContextFragmentProtocol, SituationMessagesCodec;
export 'components.dart';
export 'task.dart';
