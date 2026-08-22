import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// What the model will be used for. Maps to catalog entries.
enum GemmaPurpose {
  /// Tool-calling / structured JSON output — the agentic harness default.
  structuredToolUse('structured_tool_use'),

  /// Free-form narrative / chat text.
  chatNarrative('chat_narrative'),

  /// Summarization and compression transforms.
  summarization('summarization');

  const GemmaPurpose(this.value);

  /// [ModelPurpose] value for this purpose.
  ModelPurpose get asPurpose => ModelPurpose(value);
  final String value;
}

/// A concrete, downloadable Gemma model artifact.
class GemmaModelEntry {
  const GemmaModelEntry({
    required this.id,
    required this.purposes,
    required this.url,
    required this.sizeBytes,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.minRamGb = 4,
    this.preferredBackend,
    this.maxTokens = 1024,
  });

  final String id;
  final Set<GemmaPurpose> purposes;

  /// Direct download URL (e.g. HuggingFace .task file).
  final String url;

  /// Approximate download size, used for constraint checks and UI.
  final int sizeBytes;
  final ModelType modelType;
  final ModelFileType fileType;

  /// Minimum device RAM in GB for comfortable operation.
  final int minRamGb;
  final PreferredBackend? preferredBackend;
  final int maxTokens;

  /// Picks the smallest entry serving [purpose]. Returns null when the
  /// catalog has no entry for it.
  static GemmaModelEntry? bestFor(
    final GemmaPurpose purpose, {
    final List<GemmaModelEntry> catalog = defaultCatalog,
  }) {
    final candidates =
        catalog
            .where((final entry) => entry.purposes.contains(purpose))
            .toList()
          ..sort((final a, final b) => a.sizeBytes.compareTo(b.sizeBytes));
    return candidates.isEmpty ? null : candidates.first;
  }
}

/// Curated default catalog. Apps can override by passing their own list.
const List<GemmaModelEntry> defaultCatalog = <GemmaModelEntry>[
  // Gemma 3n E2B .task — smallest function-calling-capable Gemma.
  GemmaModelEntry(
    id: 'gemma-3n-e2b-it',
    purposes: {
      GemmaPurpose.structuredToolUse,
      GemmaPurpose.chatNarrative,
      GemmaPurpose.summarization,
    },
    url:
        'https://huggingface.co/litert-community/Gemma3n-E2B-it/resolve/main/gemma-3n-e2b-it-int4.task',
    sizeBytes: 2310000000,
    modelType: ModelType.gemmaIt,
    minRamGb: 4,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 1024,
  ),
  // Gemma 3n E4B — stronger reasoning for narrative-heavy agents.
  GemmaModelEntry(
    id: 'gemma-3n-e4b-it',
    purposes: {GemmaPurpose.chatNarrative, GemmaPurpose.summarization},
    url:
        'https://huggingface.co/litert-community/Gemma3n-E4B-it/resolve/main/gemma-3n-e4b-it-int4.task',
    sizeBytes: 4400000000,
    modelType: ModelType.gemmaIt,
    minRamGb: 6,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 2048,
  ),
];
