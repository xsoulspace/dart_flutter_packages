import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// The native text casts as router model names (ADR 0059) — the
/// `ModelRouter.inferenceClientsBuilders` keys an afm binding registers
/// the lazy clients under. Provider-owned vocabulary, like
/// `OpenRouterModelNames`.
enum NativeTextModelNames implements ModelName { qwen3, lfm25 }
