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
  symbol: 'laya_native_load',
  assetId: 'package:xsoulspace_inference_mlx_native/laya_native',
)
external int _layaNativeLoad(Pointer<Uint8> modelDir);

@Native<Pointer<Uint8> Function(Int64, Pointer<Uint8>)>(
  symbol: 'laya_native_forward',
  assetId: 'package:xsoulspace_inference_mlx_native/laya_native',
)
external Pointer<Uint8> _layaNativeForward(
  int handle,
  Pointer<Uint8> requestJson,
);

@Native<Void Function(Pointer<Uint8>)>(
  symbol: 'laya_native_free',
  assetId: 'package:xsoulspace_inference_mlx_native/laya_native',
)
external void _layaNativeFree(Pointer<Uint8> pointer);

@Native<Void Function(Int64)>(
  symbol: 'laya_native_unload',
  assetId: 'package:xsoulspace_inference_mlx_native/laya_native',
)
external void _layaNativeUnload(int handle);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32)>(
  symbol: 'laya_native_normalize',
  assetId: 'package:xsoulspace_inference_mlx_native/laya_native',
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

int rowQtype(final String type) =>
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
  static Future<NativeLayaDecisionEngine> load({final String? modelDir}) async {
    final dir = resolveModelDir(modelDir);
    final library = await Isolate.resolvePackageUri(
      Uri.parse(
        'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart',
      ),
    );
    final packageRoot = library == null
        ? null
        : File.fromUri(library).parent.parent.path;
    _ensureNativeBindingsAvailable(packageRoot: packageRoot);
    final dirNative = _toNative(dir);
    final handle = _layaNativeLoad(dirNative);
    malloc.free(dirNative);
    if (handle <= 0) {
      throw StateError(
        'laya native load failed (code $handle) for model dir $dir',
      );
    }
    final config =
        jsonDecode(File('$dir/rl_agent_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final temps = [
      for (final t in config['temperature'] as List? ?? const [1.0, 1.0, 1.0])
        clampTemperature((t as num).toDouble()),
    ];
    final buckets = <String, double>{};
    (config['temperature_by_options'] as Map? ?? const {}).forEach((
      final key,
      final value,
    ) {
      buckets['$key'] = clampTemperature((value as num).toDouble());
    });
    final tokenizer = LayaByteLevelTokenizer.load(dir, nfc: nfcNormalize);
    return NativeLayaDecisionEngine._(handle, tokenizer, temps, buckets, dir);
  }

  @override
  Map<String, String> answer(final LayaDecisionQuery query) {
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
  Map<String, LayaNativeDecision> decide(final LayaDecisionQuery query) {
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
    required final String state,
    required final Map<String, LayaTypedQuestion> questions,
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
          final scoreValue = [
            for (var i = 0; i < k; i++) i * probs[i],
          ].fold(0.0, (a, b) => a + b);
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
    final List<LayaPromptRow> rows,
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
    final List<LayaPromptRow> rows,
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
    List<List<double>> rows2(final List source) => [
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
String nfcNormalize(final String text) {
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

/// Resolves the weights directory: [override], else `LAYA_MODEL_DIR`, else
/// the fleet cache.
String resolveModelDir(final String? override) {
  final dir =
      override ??
      Platform.environment['LAYA_MODEL_DIR'] ??
      '${_home()}/.cache/xsoulspace/laya-mlx';
  if (!Directory(_expand(dir)).existsSync()) {
    throw StateError(
      'laya model dir not found: $dir (set LAYA_MODEL_DIR or fetch '
      'aac6fef/laya-mlx)',
    );
  }
  return _expand(dir);
}

String _expand(final String path) =>
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
      'liblaya_native.dylib + mlx.metallib beside the executable or in '
      '~/.cache/xsoulspace/laya/native/)',
    );
  }
}

void _ensureDylibLoaded({String? packageRoot}) {
  const dylibName = 'liblaya_native.dylib';
  final candidates = [
    ?Platform.environment['LAYA_NATIVE_DYLIB'],
    // Exe-adjacent: the `dart build cli` bundle shape (bundle/lib/).
    '${File(Platform.resolvedExecutable).parent.path}/$dylibName',
    '${File(Platform.resolvedExecutable).parent.path}/lib/$dylibName',
    if (packageRoot != null)
      '$packageRoot/native/laya_rust/target/release/$dylibName',
    // Current macOS backend before the historical Swift/iOS reference.
    // Test AOT isolates may need preload even when the parent has assets.
    'native/laya_rust/target/release/liblaya_native.dylib',
    'native/laya_native/.build/release/libLayaNative.dylib',
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
Pointer<Uint8> toNativeUtf8(final String text) => _toNative(text);

String fromNativeUtf8(final Pointer<Uint8> pointer) => _fromNative(pointer);

void ensureNativeBindingsAvailable({final String? packageRoot}) =>
    _ensureNativeBindingsAvailable(packageRoot: packageRoot);

/// The cached Qwen3 snapshot: [override], else `QWEN3_SNAPSHOT`, else the
/// Qwen3-0.6B-4bit checkout under the HF hub cache (never downloads).
String? resolveQwenSnapshotDir(final String? override) {
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
        if (snap is Directory && File('${snap.path}/config.json').existsSync()) {
          return snap.path;
        }
      }
    }
  }
  return null;
}

Pointer<Uint8> _toNative(final String text) {
  final bytes = utf8.encode(text);
  final pointer = malloc<Uint8>(bytes.length + 1);
  for (var i = 0; i < bytes.length; i++) {
    pointer[i] = bytes[i];
  }
  pointer[bytes.length] = 0;
  return pointer;
}

String _fromNative(final Pointer<Uint8> pointer) {
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
