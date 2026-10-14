import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// What the model will be used for. Maps to catalog entries.
enum GemmaPurpose {
  /// Tool-calling / structured JSON output — the agentic harness default.
  structuredToolUse('structured_tool_use'),

  /// Free-form narrative / chat text.
  chatNarrative('chat_narrative'),

  /// Summarization and compression transforms.
  summarization('summarization'),

  /// Code generation and refactoring. Desktop-only today: the smallest
  /// artifact that codes well is Gemma 4 12B (macOS/Linux). On-device coding
  /// falls back to structuredToolUse entries with a coding system prompt.
  coding('coding');

  const GemmaPurpose(this.value);

  /// [ModelPurpose] value for this purpose.
  ModelPurpose get asPurpose => ModelPurpose(value);
  final String value;
}

/// Target platforms a model artifact can run on.
///
/// Driven by flutter_gemma's format matrix: `.task` runs on Android/iOS/Web,
/// `.litertlm` runs on Android/iOS/desktop. Web needs separate `-web.task`
/// builds (not yet in this catalog).
enum GemmaPlatform { android, ios, macos, windows, linux, web }

/// A concrete, downloadable Gemma model artifact for a set of platforms.
class GemmaModelEntry {
  const GemmaModelEntry({
    required this.id,
    required this.purposes,
    required this.url,
    required this.sizeBytes,
    required this.modelType,
    required this.platforms,
    this.fileType = ModelFileType.task,
    this.minRamGb = 4,
    this.preferredBackend,
    this.maxTokens = 1024,
  });

  final String id;
  final Set<GemmaPurpose> purposes;

  /// Platforms this exact artifact supports. A purpose may need multiple
  /// entries to cover all targets (e.g. `.task` for mobile, `.litertlm` for
  /// desktop).
  final Set<GemmaPlatform> platforms;

  /// Direct download URL (e.g. HuggingFace .task or .litertlm file).
  final String url;

  /// Approximate download size, used for constraint checks and UI.
  final int sizeBytes;
  final ModelType modelType;
  final ModelFileType fileType;

  /// Minimum device RAM in GB for comfortable operation.
  final int minRamGb;
  final PreferredBackend? preferredBackend;
  final int maxTokens;

  /// Picks the smallest entry serving [purpose] on [platform]. Returns null
  /// when no entry covers that combination — callers should surface
  /// `model_not_found` rather than downloading an incompatible artifact.
  static GemmaModelEntry? bestFor(
    final GemmaPurpose purpose, {
    required final GemmaPlatform platform,
    final List<GemmaModelEntry> catalog = defaultCatalog,
  }) {
    final candidates =
        catalog
            .where(
              (final entry) =>
                  entry.purposes.contains(purpose) &&
                  entry.platforms.contains(platform),
            )
            .toList()
          ..sort((final a, final b) => a.sizeBytes.compareTo(b.sizeBytes));
    return candidates.isEmpty ? null : candidates.first;
  }
}

/// Curated default catalog, targeting Android and macOS first.
///
/// All URLs verified against the HuggingFace API (2026-08). Gemma 4 models in
/// `.litertlm` format run on Android/iOS/desktop via LiteRT-LM; the older
/// Gemma 3n `.task` artifacts are superseded and not listed.
///
/// Apps can override by passing their own list to `GemmaModelSetup`.
const List<GemmaModelEntry> defaultCatalog = <GemmaModelEntry>[
  // Gemma 4 E2B — smallest current Gemma, native function-calling chat
  // template. Verified: Android/iOS/macOS/Windows/Linux (litert-lm).
  // https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
  GemmaModelEntry(
    id: 'gemma-4-e2b-it',
    purposes: {
      GemmaPurpose.structuredToolUse,
      GemmaPurpose.chatNarrative,
      GemmaPurpose.summarization,
    },
    platforms: {GemmaPlatform.android, GemmaPlatform.ios, GemmaPlatform.macos},
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    minRamGb: 4,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 2048,
  ),
  // Gemma 4 E4B — stronger reasoning for narrative-heavy agents.
  // https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm
  GemmaModelEntry(
    id: 'gemma-4-e4b-it',
    purposes: {GemmaPurpose.chatNarrative, GemmaPurpose.summarization},
    platforms: {GemmaPlatform.android, GemmaPlatform.ios, GemmaPlatform.macos},
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/'
        'resolve/main/gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    minRamGb: 6,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 4096,
  ),
  // Gemma 4 12B — desktop coding tier. macOS/Linux only per upstream card;
  // ~30 tok/s decode on M4 GPU. Too large for phones.
  // https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm
  GemmaModelEntry(
    id: 'gemma-4-12b-it',
    purposes: {
      GemmaPurpose.coding,
      GemmaPurpose.chatNarrative,
      GemmaPurpose.summarization,
    },
    platforms: {GemmaPlatform.macos},
    url:
        'https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm/'
        'resolve/main/gemma-4-12B-it.litertlm',
    sizeBytes: 6547589312,
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    minRamGb: 16,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 4096,
  ),
];
