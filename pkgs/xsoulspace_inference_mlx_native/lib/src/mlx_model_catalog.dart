/// The curated local-model catalog (v1) for the on-device model manager
/// (`docs/design/models-local-manager.md` in the last_answer repo).
///
/// A static list — no network to browse. Every entry names an
/// MLX-converted, known-family text model under the `mlx-community` hub
/// org, so an install lands in the SAME `models--<org>--<name>` hub-cache
/// layout the Qwen3 discovery scans and needs no second registry.
///
/// The sizes are APPROXIMATIONS named before consent; the installer
/// tracks real HTTP Content-Length for progress.
// Pure data: no imports — this file must stay const-constructible.
// (The installer and the discovery own the filesystem and network laws.)
library;

/// One curated MLX-converted model the manager can install into the HF
/// hub cache.
final class MlxModelCatalogEntry {
  const MlxModelCatalogEntry({
    required this.repoId,
    required this.label,
    required this.family,
    required this.paramLabel,
    required this.quant,
    required this.approxDownloadBytes,
    this.requiredFiles = defaultRequiredFiles,
    this.optionalFiles = defaultOptionalFiles,
  });

  /// The text-file set every install needs. 404 on any of these fails
  /// the install with a named error. Model weights are NOT here — the
  /// installer resolves them separately (`model.safetensors`, else the
  /// sharded `model.safetensors.index.json` + its shards).
  static const List<String> defaultRequiredFiles = <String>[
    'config.json',
    'tokenizer.json',
    'tokenizer_config.json',
  ];

  /// Files taken when the repo has them, skipped honestly (404) when it
  /// does not.
  static const List<String> defaultOptionalFiles = <String>[
    'vocab.json',
    'merges.txt',
  ];

  /// The HF repo id, e.g. `mlx-community/Qwen3.5-0.8B-4bit`.
  final String repoId;

  /// Human display name, e.g. `Qwen3.5 0.8B`.
  final String label;

  /// The model family tag the discovery law knows: `qwen3` or `qwen3.5`.
  final String family;

  /// Human parameter count, e.g. `0.8B`.
  final String paramLabel;

  /// Quantization tag, e.g. `4bit`.
  final String quant;

  /// Approximate total download size, named in the consent dialog before
  /// the user accepts. The installer sums real Content-Lengths for
  /// progress; this only fronts the decision.
  final int approxDownloadBytes;

  /// Required per-repo text files (see [defaultRequiredFiles]).
  final List<String> requiredFiles;

  /// Optional per-repo text files (see [defaultOptionalFiles]).
  final List<String> optionalFiles;

  /// The hub org, e.g. `mlx-community`.
  String get org => repoId.split('/').first;

  /// The repo tail, e.g. `Qwen3.5-0.8B-4bit`.
  String get repoName => repoId.split('/').last;

  /// The hub-cache base directory name under the hub root, e.g.
  /// `models--mlx-community--Qwen3.5-0.8B-4bit` — the exact
  /// `models--<org>--Qwen3[.<n>]-<tail>` shape the Qwen3 discovery
  /// pattern matches.
  String get hubDirName => 'models--$org--$repoName';
}

/// The four v1 catalog entries (design `models-local-manager.md`).
///
/// The dotted `Qwen3.5-*` family is already inside the discovery law; the
/// 4bit converts are the LOADABLE form of the raw checkpoints that hit
/// the memory gate in the 2026-11-17 dogfood.
const List<MlxModelCatalogEntry> mlxModelCatalog = <MlxModelCatalogEntry>[
  MlxModelCatalogEntry(
    repoId: 'mlx-community/Qwen3-0.6B-4bit',
    label: 'Qwen3 0.6B',
    family: 'qwen3',
    paramLabel: '0.6B',
    quant: '4bit',
    approxDownloadBytes: 400 * 1024 * 1024, // ~0.4 GB
  ),
  MlxModelCatalogEntry(
    repoId: 'mlx-community/Qwen3.5-0.8B-4bit',
    label: 'Qwen3.5 0.8B',
    family: 'qwen3.5',
    paramLabel: '0.8B',
    quant: '4bit',
    approxDownloadBytes: 700 * 1024 * 1024, // ~0.7 GB
  ),
  MlxModelCatalogEntry(
    repoId: 'mlx-community/Qwen3-1.7B-4bit',
    label: 'Qwen3 1.7B',
    family: 'qwen3',
    paramLabel: '1.7B',
    quant: '4bit',
    approxDownloadBytes: 1024 * 1024 * 1024, // ~1.0 GB
  ),
  MlxModelCatalogEntry(
    repoId: 'mlx-community/Qwen3-4B-4bit',
    label: 'Qwen3 4B',
    family: 'qwen3',
    paramLabel: '4B',
    quant: '4bit',
    approxDownloadBytes: 2400 * 1024 * 1024, // ~2.4 GB
  ),
  // The `local:lfm` cast's checkpoint (2026-11-18 lifecycle law): the
  // lane resolves `*LFM2.5-1.2B*` under the SAME hub cache, so a
  // manager install here IS the lane's provisioning — without it a
  // fresh install's LFM rung can only answer `lfm2 snapshot absent` at
  // generate time. This repo ships the MLX 4bit convert directly (the
  // resolver's substring matches the org-differentiated name).
  MlxModelCatalogEntry(
    repoId: 'LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit',
    label: 'LFM 2.5 1.2B',
    family: 'lfm2.5',
    paramLabel: '1.2B',
    quant: '4bit',
    approxDownloadBytes: 630 * 1024 * 1024, // ~0.63 GB (sensed live)
  ),
  // The decision lane's brain (2026-11-19 lifecycle law): the laya-serve
  // sidecar AND the in-app decision engine resolve this checkpoint, so
  // a fresh machine provisions the lane by installing it here — the
  // same one-store law as the LFM entry (the resolver's hub scan needs
  // rl_agent_config.json + weights only). The row is DISK-ONLY: the
  // brain serves out-of-process through the sidecar, so the row carries
  // no Load/Unload — the checkpoint never occupies this app's engine.
  // fp16 weights, sensed live at 804 MB.
  MlxModelCatalogEntry(
    repoId: 'aac6fef/laya-mlx',
    label: 'Laya',
    family: 'laya',
    paramLabel: 'ModernBERT-L',
    quant: 'fp16',
    approxDownloadBytes: 804 * 1024 * 1024,
    requiredFiles: <String>['rl_agent_config.json'],
    optionalFiles: <String>[],
  ),
];
