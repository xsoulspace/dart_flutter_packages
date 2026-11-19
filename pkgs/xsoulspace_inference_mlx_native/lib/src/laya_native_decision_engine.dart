import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import 'laya_bytelevel_tokenizer.dart';
import 'laya_decision_server.dart';
import 'laya_prompt.dart';

// Native bindings — resolved through the package's native-assets code asset
// (hook/build.dart builds the current Rust/MLX macOS backend and registers it).
// On machines without the Apple toolchain the hook registers no asset and
// these throw a named error at first call; the golden test skips honestly.

@Native<Int64 Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_load',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _layaNativeLoad(Pointer<Uint8> modelDir);

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'mlx_native_forward',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external Pointer<Uint8> _layaNativeForward(
  int handle,
  Pointer<Uint8> requestJson,
);

@Native<Void Function(Pointer<Uint8>)>(
  symbol: 'mlx_native_free',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external void _layaNativeFree(Pointer<Uint8> pointer);

@Native<Void Function(Int64)>(
  symbol: 'mlx_native_unload',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external void _layaNativeUnload(int handle);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32)>(
  symbol: 'mlx_native_normalize',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _layaNativeNormalize(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int outCap,
);

/// One calibrated decision per question: the chosen option id, the full
/// probability distribution (insertion order of the question's criteria),
/// and the two confidence readings the reference runtime publishes.
final class LayaNativeDecision {
  const LayaNativeDecision({
    required this.optionId,
    required this.probabilities,
    required this.confidence,
    required this.answerConfidence,
  });

  final String optionId;
  final Map<String, double> probabilities;
  final double confidence;
  final double answerConfidence;
}

/// A typed decision (choice/score/noul) with the reference runtime's
/// published fields.
final class LayaTypedDecision {
  const LayaTypedDecision({
    required this.type,
    this.choice,
    this.score,
    this.noul,
    required this.probabilities,
    required this.confidence,
    required this.answerConfidence,
    required this.actProbability,
  });

  final String type;

  /// choice: the chosen label.
  final String? choice;

  /// score: the expected level (Σ i · p[i]).
  final double? score;

  /// noul: p(true).
  final double? noul;

  /// choice: label→p; score: level index→p; noul: 'false'/'true'→p.
  final Map<String, double> probabilities;
  final double confidence;
  final double answerConfidence;

  /// The action head's escalate probability (p[1] of the action softmax).
  final double actProbability;
}

int rowQtype(String type) =>
    const {'choice': 0, 'score': 1, 'noul': 2}[type] ?? 0;

/// The real Laya model (laya-mlx checkpoint) answering through the native
/// MLX runtime via `dart:ffi` — the `LayaDecisionEngine` seam's native
/// runtime, wired through Dart native assets.
///
/// Dart owns everything around the model: the byte-level BPE tokenizer, NFC
/// normalization (dispatched to the dylib), prompt construction, batching,
/// and temperature calibration. The native side is a pure forward pass
/// (ModernBERT-large + decision head) over token ids.
final class NativeLayaDecisionEngine implements CalibratedLayaDecisionEngine {
  NativeLayaDecisionEngine._(
    this._handle,
    this._tokenizer,
    this.temperature,
    this.temperatureByOptions,
    this.modelDir,
  );

  final int _handle;
  final LayaByteLevelTokenizer _tokenizer;
  final List<double> temperature;
  final Map<String, double> temperatureByOptions;
  final String modelDir;

  /// Loads the model. Weights: [modelDir], else `LAYA_MODEL_DIR`, else
  /// `~/.cache/xsoulspace/laya-mlx` (fetch aac6fef/laya-mlx — the runtime
  /// never downloads).
  static Future<NativeLayaDecisionEngine> load({String? modelDir}) async {
    final dir = resolveModelDir(modelDir);
    final packageRoot = await resolveNativePackageRoot();
    _ensureNativeBindingsAvailable(packageRoot: packageRoot);
    final dirNative = _toNative(dir);
    final handle = _layaNativeLoad(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) {
      throw StateError(
        'laya native load failed (code $handle) for model dir $dir',
      );
    }
    final config = jsonDecode(
      File('$dir/rl_agent_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final temps = [
      for (final t in config['temperature'] as List? ?? const [1.0, 1.0, 1.0])
        clampTemperature((t as num).toDouble()),
    ];
    final buckets = <String, double>{};
    (config['temperature_by_options'] as Map? ?? const {}).forEach((
      key,
      value,
    ) {
      buckets['$key'] = clampTemperature((value as num).toDouble());
    });
    final tokenizer = LayaByteLevelTokenizer.load(dir, nfc: nfcNormalize);
    return NativeLayaDecisionEngine._(handle, tokenizer, temps, buckets, dir);
  }

  @override
  Map<String, String> answer(LayaDecisionQuery query) {
    final decisions = decide(query);
    return {
      for (final entry in decisions.entries) entry.key: entry.value.optionId,
    };
  }

  @override
  Map<String, LayaDecisionResult> answerDecisions(LayaDecisionQuery query) {
    final typed = decideTyped(
      state: query.state,
      questions: {
        for (final entry in query.questions.entries)
          entry.key: LayaTypedQuestion.choice(entry.value.instructions, {
            for (final criterion in entry.value.criteria.entries)
              criterion.key: renderLayaCriterion(criterion.value),
          }),
      },
    );
    return {
      for (final entry in typed.entries)
        entry.key: LayaDecisionResult(
          optionId: entry.value.choice!,
          probabilities: entry.value.probabilities,
          confidence: entry.value.confidence,
          answerConfidence: entry.value.answerConfidence,
          actProbability: entry.value.actProbability,
        ),
    };
  }

  /// The full calibrated distribution per choice question — the honest
  /// output the wire server and tests read.
  Map<String, LayaNativeDecision> decide(LayaDecisionQuery query) {
    final typed = decideTyped(
      state: query.state,
      questions: {
        for (final entry in query.questions.entries)
          entry.key: LayaTypedQuestion.choice(entry.value.instructions, {
            for (final criterion in entry.value.criteria.entries)
              criterion.key: renderLayaCriterion(criterion.value),
          }),
      },
    );
    return {
      for (final entry in typed.entries)
        entry.key: LayaNativeDecision(
          optionId: entry.value.choice!,
          probabilities: entry.value.probabilities,
          confidence: entry.value.confidence,
          answerConfidence: entry.value.answerConfidence,
        ),
    };
  }

  /// The full choice/score/noul surface over the typed prompt path.
  Map<String, LayaTypedDecision> decideTyped({
    required String state,
    required Map<String, LayaTypedQuestion> questions,
  }) {
    final rows = <LayaPromptRow>[];
    final keys = questions.keys.toList();
    for (final id in keys) {
      final question = questions[id]!;
      final row = buildTypedSequence(
        tokenizer: _tokenizer,
        state: state,
        question: question,
      );
      final optionCount = renderTypedOptions(question).length;
      if (row.markers.length != optionCount) {
        throw StateError('question $id: options do not fit the token budget');
      }
      rows.add(row);
    }
    final (logits, act) = forwardRows(rows);
    final result = <String, LayaTypedDecision>{};
    for (var r = 0; r < keys.length; r++) {
      final question = questions[keys[r]]!;
      final qtype = rowQtype(question.type);
      final k = renderTypedOptions(question).length;
      final scale =
          temperatureByOptions[tempBucketKey(qtype, k)] ?? temperature[qtype];
      final z = [for (var i = 0; i < k; i++) logits[r][i] / scale];
      final maxZ = z.reduce(math.max);
      final exps = [for (final v in z) math.exp(v - maxZ)];
      final sum = exps.fold(0.0, (a, b) => a + b);
      final probs = [for (final e in exps) e / sum];
      var best = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[best]) best = i;
      }
      final actTop = math.max(act[r][0], act[r][1]);
      final actExp = [
        math.exp(act[r][0] - actTop),
        math.exp(act[r][1] - actTop),
      ];
      final actSum = actExp[0] + actExp[1];
      switch (question.type) {
        case 'choice':
          final labels = question.criteria!.keys.toList();
          result[keys[r]] = LayaTypedDecision(
            type: 'choice',
            choice: labels[best],
            probabilities: {for (var i = 0; i < k; i++) labels[i]: probs[i]},
            confidence: confidenceFromProbs(probs, k),
            answerConfidence: probs.reduce(math.max),
            actProbability: actExp[0] / actSum,
          );
        case 'score':
          final scoreValue = [for (var i = 0; i < k; i++) i * probs[i]]
              .fold(0.0, (a, b) => a + b);
          result[keys[r]] = LayaTypedDecision(
            type: 'score',
            score: scoreValue,
            probabilities: {for (var i = 0; i < k; i++) '$i': probs[i]},
            confidence: confidenceFromProbs(probs, k),
            answerConfidence: probs.reduce(math.max),
            actProbability: actExp[0] / actSum,
          );
        case 'noul':
          result[keys[r]] = LayaTypedDecision(
            type: 'noul',
            noul: probs[1],
            probabilities: {'false': probs[0], 'true': probs[1]},
            confidence: math.max(probs[1], 1 - probs[1]),
            answerConfidence: probs.reduce(math.max),
            actProbability: actExp[0] / actSum,
          );
      }
    }
    return result;
  }

  /// Raw float32 decision and action logits, in request-row order.
  ///
  /// The current native heterogeneous-batch path changes shorter question
  /// outputs. Execute rows independently until that kernel's batch contract
  /// passes the frozen oracle. This retains all question kinds and one shared
  /// model, at the explicit cost of one native forward per question.
  (List<List<double>>, List<List<double>>) forwardRows(
    List<LayaPromptRow> rows,
  ) {
    if (rows.length <= 1) return _forwardBatch(rows);
    final width = rows.fold<int>(
      2,
      (max, row) => math.max(max, row.markers.length),
    );
    final logits = <List<double>>[];
    final actions = <List<double>>[];
    for (final row in rows) {
      final (rowLogits, rowActions) = _forwardBatch([row]);
      logits.add([
        ...rowLogits.single,
        for (var i = rowLogits.single.length; i < width; i++) -1e4,
      ]);
      actions.add(rowActions.single);
    }
    return (logits, actions);
  }

  (List<List<double>>, List<List<double>>) _forwardBatch(
    List<LayaPromptRow> rows,
  ) {
    final request = jsonEncode({
      'batch': [
        for (final row in rows)
          {'ids': row.ids, 'markers': row.markers, 'qtype': row.qtype},
      ],
    });
    final requestNative = _toNative(request);
    final responseNative = _layaNativeForward(_handle, requestNative);
    malloc.free(requestNative);
    if (responseNative == nullptr) {
      throw StateError('laya native forward returned null');
    }
    final response = _fromNative(responseNative);
    _layaNativeFree(responseNative);
    final decoded = jsonDecode(response);
    if (decoded is Map && decoded['error'] is String) {
      throw StateError('laya native forward failed: ${decoded['error']}');
    }
    final logits = (decoded as Map)['logits'];
    final act = decoded['act'];
    if (logits is! List || act is! List) {
      throw StateError('laya native forward: missing logits/act');
    }
    List<List<double>> rows2(List source) => [
      for (final row in source)
        [for (final v in row as List) (v as num).toDouble()],
    ];
    return (rows2(logits), rows2(act));
  }

  void dispose() {
    _layaNativeUnload(_handle);
  }
}

/// NFC (canonical composed) normalization through the dylib — the
/// checkpoint tokenizer's normalizer.
String nfcNormalize(String text) {
  final src = _toNative(text);
  var capacity = utf8.encode(text).length * 4 + 16;
  var out = malloc<Uint8>(capacity);
  var written = _layaNativeNormalize(src, out, capacity);
  if (written < 0) {
    malloc.free(out);
    capacity *= 2;
    out = malloc<Uint8>(capacity);
    written = _layaNativeNormalize(src, out, capacity);
    if (written < 0) {
      malloc.free(out);
      malloc.free(src);
      throw StateError('laya native NFC normalization failed');
    }
  }
  final result = _fromNative(out);
  malloc.free(out);
  malloc.free(src);
  return result;
}

/// Resolves the weights directory: [override] or `LAYA_MODEL_DIR` when
/// set and present, else the HF hub cache (the manager's one store —
/// the row's Delete IS the lane's un-provisioning), else the legacy
/// fleet cache (pre-manager machines).
String resolveModelDir(String? override) {
  final pinned = override ?? Platform.environment['LAYA_MODEL_DIR'];
  if (pinned != null) {
    final dir = _expand(pinned);
    if (Directory(dir).existsSync()) return dir;
  }
  // The one-store law (2026-11-18, the lfm2 resolver's twin; 2026-11-19
  // order): the hub cache LEADS so the manager row stays the truth (a
  // hub install provisions the lane without a second copy of the
  // weights), and the legacy xsoulspace cache keeps pre-manager
  // machines working.
  final hubDir = _hubLayaDir();
  if (hubDir != null) return hubDir;
  final legacy = '${_home()}/.cache/xsoulspace/laya-mlx';
  if (Directory(_expand(legacy)).existsSync()) return _expand(legacy);
  throw StateError(
    'laya model dir not found: ${pinned ?? '(none pinned)'} (set '
    'LAYA_MODEL_DIR, fetch aac6fef/laya-mlx, or install it through the '
    'model manager)',
  );
}

/// The newest resolvable `laya-mlx` snapshot under the HF hub cache, or
/// null — the dangling-blob law applies (the checkpoint counts only
/// when its config AND its weights are actually readable).
String? _hubLayaDir() {
  final home = _home();
  final hub = Directory('$home/.cache/huggingface/hub');
  if (!hub.existsSync()) return null;
  for (final entry in hub.listSync()) {
    if (!entry.path.contains('laya-mlx')) continue;
    final snapshots = Directory('${entry.path}/snapshots');
    if (!snapshots.existsSync()) continue;
    for (final snap in snapshots.listSync()) {
      if (snap is! Directory) continue;
      if (!File('${snap.path}/rl_agent_config.json').existsSync()) {
        continue;
      }
      if (File('${snap.path}/model.safetensors').existsSync()) {
        return snap.path;
      }
      final index = File('${snap.path}/model.safetensors.index.json');
      if (index.existsSync()) return snap.path;
    }
  }
  return null;
}

String _expand(String path) =>
    path.startsWith('~') ? path.replaceFirst('~', _home()) : path;

/// Guarantees the native symbols are callable before the first forward.
///
/// Under `dart run` / `dart build cli` the native-assets manifest resolves
/// the bindings and the probe succeeds without any preload (preloading here
/// anyway would load the dylib a second time through a different path —
/// ObjC class duplication and split state). `dart compile exe` does not
/// bundle code assets: its first call fails asset resolution, so we preload
/// the dylib via [DynamicLibrary.open] from the resolver chain — a
/// successful open registers the symbols in the process where the @Native
/// bindings' RTLD_DEFAULT fallback finds them — and the probe retries.
void _ensureNativeBindingsAvailable({String? packageRoot}) {
  try {
    nfcNormalize('laya');
    return;
  } on Object {
    _ensureDylibLoaded(packageRoot: packageRoot);
  }
  try {
    nfcNormalize('laya');
  } on Object {
    throw StateError(
      'laya native runtime unavailable: no native-assets code asset (build '
      'with `dart build cli`, not `dart compile exe`) and no preloadable '
      'dylib in the resolver chain (set LAYA_NATIVE_DYLIB, or place '
      'libmlx_native.dylib + mlx.metallib beside the executable or in '
      '~/.cache/xsoulspace/laya/native/)',
    );
  }
}

void _ensureDylibLoaded({String? packageRoot}) {
  const dylibName = 'libmlx_native.dylib';
  final candidates = [
    ?Platform.environment['LAYA_NATIVE_DYLIB'],
    // Exe-adjacent: the `dart build cli` bundle shape (bundle/lib/).
    '${File(Platform.resolvedExecutable).parent.path}/$dylibName',
    '${File(Platform.resolvedExecutable).parent.path}/lib/$dylibName',
    if (packageRoot != null)
      '$packageRoot/native/mlx_native/target/release/$dylibName',
    // Current macOS backend (crate-relative). The historical Swift host
    // (libLayaNative.dylib) is git history only — no load candidate.
    // Test AOT isolates may need preload even when the parent has assets.
    'native/mlx_native/target/release/libmlx_native.dylib',
    '${_home()}/.cache/xsoulspace/laya/native/$dylibName',
  ];
  for (final candidate in candidates) {
    final path = _expand(candidate);
    if (!File(path).existsSync()) continue;
    try {
      DynamicLibrary.open(path);
      return;
    } on Object {
      // Try the next candidate; the @Native resolution reports the final
      // failure with the manifest context.
    }
  }
}

String _home() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is not set; cannot resolve laya artifacts');
  }
  return home;
}

/// Public shims for sibling native-client files (the qwen text engine).
/// Flutter bundles native assets but does not expose package URI resolution.
/// Package-relative preload is optional; native-assets probing stays first.
Future<String?> resolveNativePackageRoot() async {
  try {
    final library = await Isolate.resolvePackageUri(
      Uri.parse(
        'package:xsoulspace_inference_mlx_native/'
        'xsoulspace_inference_mlx_native.dart',
      ),
    );
    return library == null ? null : File.fromUri(library).parent.parent.path;
  } on UnsupportedError {
    return null;
  }
}

Pointer<Uint8> toNativeUtf8(String text) => _toNative(text);

String fromNativeUtf8(Pointer<Uint8> pointer) => _fromNative(pointer);

void ensureNativeBindingsAvailable({String? packageRoot}) =>
    _ensureNativeBindingsAvailable(packageRoot: packageRoot);

/// The cached Qwen3 snapshot: [override], else `QWEN3_SNAPSHOT`, else the
/// Qwen3-0.6B-4bit checkout under the HF hub cache (never downloads).
String? resolveQwenSnapshotDir(String? override) {
  if (override != null) return override;
  final env = Platform.environment['QWEN3_SNAPSHOT'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final hub = Directory('$home/.cache/huggingface/hub');
  if (!hub.existsSync()) return null;
  for (final entry in hub.listSync()) {
    if (entry.path.contains('Qwen3-0.6B-4bit')) {
      final snapshots = Directory('${entry.path}/snapshots');
      if (!snapshots.existsSync()) continue;
      for (final snap in snapshots.listSync()) {
        if (snap is Directory &&
            File('${snap.path}/config.json').existsSync() &&
            qwenSnapshotWeightsResolve(snap.path)) {
          return snap.path;
        }
      }
    }
  }
  return null;
}

/// One cached Qwen3 text cast discovered under the HF hub cache.
final class CachedQwen3Snapshot {
  const CachedQwen3Snapshot({
    required this.refName,
    required this.paramLabel,
    required this.snapshotDir,
    this.org = 'mlx-community',
  });

  /// The hub-cache org the snapshot came from (`mlx-community` = the
  /// MLX-converted, loadable form; the raw `Qwen` org checkpoints
  /// shadow the same refName but the native engine cannot load them —
  /// the collision law prefers the convert).
  final String org;

  /// Ref-friendly lowercase name, e.g. `qwen3-1.7b` (the trailing `4bit`
  /// quant tag is dropped — the default quant stays unnamed; other quants
  /// keep theirs, e.g. `qwen3-0.6b-bf16`, so distinct checkpoints never
  /// collide).
  final String refName;

  /// Human parameter count parsed from the checkpoint name, e.g. `1.7B`;
  /// the raw name when no size token is present.
  final String paramLabel;

  /// The snapshot directory (contains `config.json`).
  final String snapshotDir;
}

/// Hub-cache organizations whose Qwen3-family casts join the discovered
/// surface: `mlx-community` (the MLX-converted `Qwen3-*` casts) and `Qwen`
/// (the org's own checkpoints, e.g. the dotted `Qwen3.5-*` family). Any
/// other org is not a discovered cast, whatever its model name.
const Set<String> _qwen3HubOrgs = {'mlx-community', 'Qwen'};

/// Matches a `models--<org>--Qwen3[.<n>]-<model>` hub-cache base name:
/// group 1 = org, group 2 = family (`Qwen3` or dotted `Qwen3.5`),
/// group 3 = the model tail (e.g. `1.7B-4bit`, `0.6B-bf16`, `0.8B`).
final RegExp _qwen3HubDirPattern = RegExp(
  r'^models--([A-Za-z0-9_.-]+)--(Qwen3(?:\.\d+)?)-(.*)$',
);

/// Derives a [CachedQwen3Snapshot] from one
/// `models--<org>--Qwen3[.<n>]-<Name>` hub-cache directory (org in
/// [_qwen3HubOrgs]), or null when the name is not a Qwen3 text cast or
/// no complete snapshot (config.json) is checked out.
/// Whether the snapshot's weights actually resolve on disk: a
/// `model.safetensors` whose bytes exist (single-file layout), or an
/// index whose at least one shard file exists (the sharded layout).
/// `existsSync` follows symlinks, so a DANGLING cache entry — the shared
/// blob target wiped, the 2026-11-18 Qwen3-0.6B-4bit live failure whose
/// load answered a bare `code -2` — passes a config-only check and then
/// fails the weight load; the scan refuses it here instead, honestly, at
/// discovery time.
bool qwenSnapshotWeightsResolve(String snapshotDir) {
  if (File('$snapshotDir/model.safetensors').existsSync()) return true;
  final index = File('$snapshotDir/model.safetensors.index.json');
  if (!index.existsSync()) return false;
  try {
    final doc = jsonDecode(index.readAsStringSync()) as Map<String, dynamic>;
    final map = doc['weight_map'];
    if (map is! Map) return false;
    for (final shard in map.values.toSet()) {
      if (shard is String && File('$snapshotDir/$shard').existsSync()) {
        return true;
      }
    }
  } on FormatException {
    return false;
  }
  return false;
}

CachedQwen3Snapshot? cachedQwen3SnapshotFromDir(String dirPath) {
  final base = dirPath.split(Platform.pathSeparator).last;
  final match = _qwen3HubDirPattern.firstMatch(base);
  if (match == null) return null;
  if (!_qwen3HubOrgs.contains(match.group(1)!)) return null;
  final family = match.group(2)!; // `Qwen3` | `Qwen3.5`
  var model = match.group(3)!; // e.g. `1.7B-4bit`, `0.6B-bf16`, `0.8B`
  final snapshots = Directory('$dirPath/snapshots');
  if (!snapshots.existsSync()) return null;
  String? dir;
  for (final snap in snapshots.listSync()) {
    if (snap is! Directory) continue;
    if (!File('${snap.path}/config.json').existsSync()) continue;
    // The weights must resolve too (the dangling-symlink law): a
    // config-only dir loads nothing and surfaces the failure as a bare
    // native code at reply time — not a discoverable variant.
    if (!qwenSnapshotWeightsResolve(snap.path)) continue;
    dir = snap.path;
    break;
  }
  if (dir == null) return null;
  final quantMatch = RegExp(r'-(4bit|8bit|bf16|fp16|iq\w+|q\w+)$')
      .firstMatch(model.toLowerCase());
  var quantTag = '';
  if (quantMatch != null && quantMatch.group(1) != '4bit') {
    quantTag = '-${quantMatch.group(1)}';
  }
  if (quantMatch != null) {
    model = model.substring(0, model.length - quantMatch.group(0)!.length);
  }
  final sizeMatch = RegExp(r'(\d+(?:\.\d+)?)b', caseSensitive: false)
      .firstMatch(model);
  final paramLabel = sizeMatch == null
      ? model
      : '${sizeMatch.group(1)}B';
  return CachedQwen3Snapshot(
    refName:
        '${family.toLowerCase()}-${model.toLowerCase().replaceAll('_', '-')}$quantTag'
            .replaceAll(RegExp(r'-+'), '-'),
    paramLabel: paramLabel,
    snapshotDir: dir,
    org: match.group(1)!,
  );
}

/// Every cached Qwen3-family cast under the HF hub cache (orgs in
/// [_qwen3HubOrgs]: the mlx-community `Qwen3-*` converts and the Qwen
/// org's own checkpoints, dotted families like `Qwen3.5-*` included),
/// sorted by directory name. Empty when the cache is absent. Never
/// downloads; a missing HOME or hub directory simply names nothing.
/// [hubRoot] overrides the hub directory (tests).
List<CachedQwen3Snapshot> listCachedQwen3Snapshots({String? hubRoot}) {
  final root =
      hubRoot ??
      () {
        final home = Platform.environment['HOME'];
        return home == null ? null : '$home/.cache/huggingface/hub';
      }();
  if (root == null) return const <CachedQwen3Snapshot>[];
  final hub = Directory(root);
  if (!hub.existsSync()) return const <CachedQwen3Snapshot>[];
  // Same-refName collision law (2026-11-18, the live dogfood's load
  // failure): the RAW `Qwen/Qwen3.5-0.8B` org checkpoint and the
  // `mlx-community` 4bit convert share one refName, and the sorted
  // dir scan used to let the raw one win — a layout the native engine
  // refuses (code -2). The CONVERTED org is the loadable form: it
  // wins the dedupe regardless of directory sort order.
  final byRef = <String, CachedQwen3Snapshot>{};
  final dirs = hub.listSync().map((e) => e.path).toList()..sort();
  for (final dirPath in dirs) {
    final snapshot = cachedQwen3SnapshotFromDir(dirPath);
    if (snapshot == null) continue;
    final held = byRef[snapshot.refName];
    if (held == null ||
        (held.org != 'mlx-community' && snapshot.org == 'mlx-community')) {
      byRef[snapshot.refName] = snapshot;
    }
  }
  final found = byRef.values.toList()
    ..sort((a, b) => a.snapshotDir.compareTo(b.snapshotDir));
  return found;
}

/// Resolves a specific named Qwen3 variant, e.g. `qwen3-1.7b`, against the
/// hub-cache scan ([listCachedQwen3Snapshots]). Null when no cached
/// snapshot names that variant (callers skip honestly — never download).
/// [hubRoot] overrides the hub directory (tests).
String? resolveQwen3SnapshotVariant(String variant, {String? hubRoot}) {
  final name = variant.trim().toLowerCase();
  if (name.isEmpty) return null;
  for (final snapshot in listCachedQwen3Snapshots(hubRoot: hubRoot)) {
    if (snapshot.refName == name) return snapshot.snapshotDir;
  }
  return null;
}

Pointer<Uint8> _toNative(String text) {
  final bytes = utf8.encode(text);
  final pointer = malloc<Uint8>(bytes.length + 1);
  for (var i = 0; i < bytes.length; i++) {
    pointer[i] = bytes[i];
  }
  pointer[bytes.length] = 0;
  return pointer;
}

String _fromNative(Pointer<Uint8> pointer) {
  final bytes = <int>[];
  var i = 0;
  while (true) {
    final byte = pointer[i];
    if (byte == 0) break;
    bytes.add(byte);
    i++;
  }
  return utf8.decode(bytes);
}
