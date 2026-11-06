// ws1_replay.dart - WS-1 LIVE replay driver (PROGRAM.md Phase B).
//
// Turns the A3 plant-1 (arm-002) RECOVERED removal edit into a typed patch
// artifact (bridge.sidecarDeltaToPatch -> PatchEntry) and replays it end to
// end against A3's OWN builder scripts, reused UNCHANGED:
//
//   1 provenance   every input artifact's sha256 is checked against the
//                  recorded digests (join-table.json pinned by
//                  A3-verdict-final.json, per-arm rows in A3-run.jsonl,
//                  mirror_receipt / repair_receipt / repair_spec / recovered
//                  in the blind arm dir, base snapshot shard digest)
//   2 rebuild M    apply_delta.py (frozen) on the repo truth specs +
//                  make_mirror.py on the base snapshot; the rebuilt mirror
//                  store sha256 MUST equal the recorded mirror_shard_sha256
//   3 typed patch  sidecarDeltaToPatch(spec, baseFingerprint: recorded M
//                  mirror digest) -> patchToSidecarSpec canonicalization ->
//                  patch_algebra apply against the REAL exported M window
//                  (actual fingerprint = rebuilt M store digest; a moved
//                  base refuses with the algebra's NAMED STALE_PRECONDITION)
//   4 rebuild R    apply_delta.py on the canonical typed spec (base = rebuilt
//                  M mirror) + make_mirror.py; every rebuilt post-repair
//                  tensor f32 digest MUST equal the recorded
//                  post_repair_tensor_f32_sha256 (A3's repair stage was
//                  in-memory: those per-tensor digests ARE the recorded R
//                  mirror commitments; the R store sha is observed-only)
//   5 receipts     per tensor one ledger `edit` row (editRowPayload commits
//                  patch + recorded digests) and one `replay` row carrying
//                  the ReplayReceipt {patch_digest, mirror_digest,
//                  battery_digest, reproduced}, plus one `ws1-verdict` row
//
// FALSIFIER LAW: any bit-identity mismatch is recorded as NAMED
// REPLAY_DIGEST_DRIFT (with the differing digests) in a `ws1-refusal` ledger
// row and the driver STOPS - drift is never fudged, never retried.
//
// House laws honored: mirrors + windows live under --work in $TMPDIR and are
// swept at the end (probe scratch law); durable evidence is the textual
// jsonl ledger; Python runners set PYTHONDONTWRITEBYTECODE=1; no device or
// model runs (pure digest arithmetic + the frozen CPU-side builders).
//
// usage: dart run ws1_replay.dart --arm-dir <blind/arm-NNN> --base <snapshot>
//     --work <$TMPDIR/wm-ws1> --python <venv-python> --repo <package-root>
//     [--out <receipts/WS1-replay.jsonl>] [--keep-work]
//
// Exit: 0 = replay complete (verdict row says PASS); 1 = NAMED refusal (row
// appended, stderr 'CODE: detail'); 64 = usage.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

/// Returns null when [recorded] and [rebuilt] agree; otherwise the NAMED
/// WS-1 falsifier string carrying BOTH digests (never just one side).
String? ws1DigestDrift({
  required String label,
  required String recorded,
  required String rebuilt,
}) {
  if (recorded == rebuilt) return null;
  return 'REPLAY_DIGEST_DRIFT $label recorded=$recorded rebuilt=$rebuilt';
}

/// The WS-1 verdict label: PASS only when NO digest drifted and every
/// replay receipt reproduced; otherwise FAIL(REPLAY_DIGEST_DRIFT).
String ws1VerdictOf(List<String> drifts, List<bool> reproduced) {
  final ok = drifts.isEmpty && reproduced.every((r) => r);
  return ok ? 'PASS' : 'FAIL(REPLAY_DIGEST_DRIFT)';
}

class _Ws1Error implements Exception {
  _Ws1Error(this.code, this.detail, {this.step});
  final String code;
  final String detail;
  final String? step;
  @override
  String toString() => '$code${step == null ? '' : ' step=$step'}: $detail';
}

Future<String> _sha256OfFile(String path) async {
  if (!File(path).existsSync()) {
    throw _Ws1Error('FILE_MISSING', path);
  }
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

Object? _req(Map<String, Object?> m, String key) {
  if (!m.containsKey(key)) {
    throw _Ws1Error('MISSING_FIELD', '$key in ${m.keys.toList()}');
  }
  return m[key];
}

String _reqStr(Map<String, Object?> m, String key) {
  final v = _req(m, key);
  if (v is! String || v.isEmpty) {
    throw _Ws1Error('MALFORMED_FIELD', '$key expected=non-empty String');
  }
  return v;
}

Map<String, Object?> _reqMap(Map<String, Object?> m, String key) {
  final v = _req(m, key);
  if (v is! Map) {
    throw _Ws1Error(
        'MALFORMED_FIELD', '$key expected=Map found=${v.runtimeType}');
  }
  return v.cast<String, Object?>();
}

List<Object?> _reqList(Map<String, Object?> m, String key) {
  final v = _req(m, key);
  if (v is! List) {
    throw _Ws1Error(
        'MALFORMED_FIELD', '$key expected=List found=${v.runtimeType}');
  }
  return v;
}

Map<String, Object?> _readJson(String path) {
  if (!File(path).existsSync()) throw _Ws1Error('FILE_MISSING', path);
  try {
    return (jsonDecode(File(path).readAsStringSync()) as Map)
        .cast<String, Object?>();
  } on FormatException catch (e) {
    throw _Ws1Error('JSON_MALFORMED', '$path (${e.message})');
  }
}

bool _numsEqual(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x is! num || y is! num || x != y) return false;
  }
  return true;
}

String _layerOf(String tensorName) {
  final m = RegExp(r'\.layers\.(\d+)\.').firstMatch(tensorName);
  if (m == null) {
    throw _Ws1Error('TENSOR_NAME_UNPARSEABLE', tensorName);
  }
  return m.group(1)!;
}

/// Runs one frozen Python builder step; returns stdout. Non-zero exit is a
/// NAMED error (the builders' own 'CODE: detail' stderr vocabulary).
String _runStep(String step, String python, String script, List<String> argv) {
  final proc = Process.runSync(
    python,
    ['-I', script, ...argv],
    environment: {'PYTHONDONTWRITEBYTECODE': '1'},
    includeParentEnvironment: true,
  );
  if (proc.exitCode != 0) {
    final errText = (proc.stderr as String).trim();
    final first = errText.split('\n').first;
    final code = first.contains(':') ? first.split(':').first : '';
    throw _Ws1Error(
      code.isEmpty ? 'UNNAMED_FAILURE' : code,
      errText.isEmpty ? (proc.stdout as String).trim() : errText,
      step: step,
    );
  }
  return (proc.stdout as String).trim();
}

/// Reads the raw little-endian f64 window export into a [Tensor].
Tensor _readWindowF64(String path, int rows, int width) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.length != rows * width * 8) {
    throw _Ws1Error(
      'WINDOW_EXPORT_MALFORMED',
      '$path bytes=${bytes.length} expected=${rows * width * 8}',
    );
  }
  final bd = ByteData.sublistView(bytes);
  final t = Tensor(rows, width);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < width; c++) {
      t.set(r, c, bd.getFloat64((r * width + c) * 8, Endian.little));
    }
  }
  return t;
}

/// The sidecar spec digest apply_delta.py recorded for [tensorName] inside
/// the A3 mirror receipt's edited rows (what the A3 run consumed).
String _recordedSpecDigest(
    Map<String, Object?> mirrorReceipt, String tensorName) {
  for (final e in _reqList(mirrorReceipt, 'edited')) {
    final m = (e as Map).cast<String, Object?>();
    if (m['tensor'] == tensorName) {
      return _reqStr(m, 'sidecar_receipt_spec_digest');
    }
  }
  throw _Ws1Error('MIRROR_RECEIPT_ROW_MISSING', tensorName);
}

Future<void> main(List<String> args) async {
  // ---- args ----
  String? armDir;
  String? base;
  String? work;
  String? python;
  String? repo;
  String? outPath;
  var keepWork = false;
  for (var i = 0; i < args.length; i++) {
    String next() {
      if (i + 1 >= args.length) {
        throw _Ws1Error('ARG_MISSING', 'value for ${args[i]}');
      }
      return args[++i];
    }

    switch (args[i]) {
      case '--arm-dir':
        armDir = next();
        break;
      case '--base':
        base = next();
        break;
      case '--work':
        work = next();
        break;
      case '--python':
        python = next();
        break;
      case '--repo':
        repo = next();
        break;
      case '--out':
        outPath = next();
        break;
      case '--keep-work':
        keepWork = true;
        break;
      default:
        stderr.writeln('ARG_UNKNOWN: ${args[i]}');
        exit(64);
    }
  }
  if (armDir == null ||
      base == null ||
      work == null ||
      python == null ||
      repo == null) {
    stderr.writeln(
      'usage: dart run ws1_replay.dart --arm-dir <dir> --base <snapshot> '
      '--work <tmpdir> --python <venv-python> --repo <package-root> '
      '[--out <jsonl>] [--keep-work]',
    );
    exit(64);
  }
  final outFile = File(outPath ?? '$repo/receipts/WS1-replay.jsonl');

  Future<Never> refuse(String code, String detail,
      {String? step, Map<String, Object?> extra = const {}}) async {
    append(outFile, 'ws1-refusal', {
      'ws': 'WS-1',
      'mode': 'live',
      'code': code,
      'step': ?step,
      'detail': detail,
      ...extra,
      'at': DateTime.now().toUtc().toIso8601String(),
      'wall_ms_claim': false,
    });
    stderr.writeln('$code${step == null ? '' : ' step=$step'}: $detail');
    exit(1);
  }

  final applyDelta = '$repo/tool/eval/apply_delta.py';
  final makeMirror = '$repo/tool/runs/make_mirror.py';
  final exportWindow = '$repo/tool/runs/ws1_export_window.py';
  final joinTablePath = '$repo/receipts/A3/join-table.json';
  final verdictFinalPath = '$repo/receipts/A3/A3-verdict-final.json';
  final runJsonlPath = '$repo/receipts/A3-run.jsonl';
  final truthSpecs = '$repo/receipts/A3/truth/specs/a3-plant-1';

  try {
    // ---- 1. recorded artifacts + provenance ----
    final verdictFinal = _readJson(verdictFinalPath);
    final joinTable = _readJson(joinTablePath);
    final mirrorReceipt = _readJson('$armDir/mirror_receipt.json');
    final repairReceipt = _readJson('$armDir/repair_receipt.json');
    final repairSpec = _readJson('$armDir/repair_spec.json');
    final recovered = _readJson('$armDir/recovered.json');
    if (!File(runJsonlPath).existsSync()) {
      throw _Ws1Error('FILE_MISSING', runJsonlPath);
    }

    Future<void> provenance(
        String label, String recorded, String actual) async {
      final drift =
          ws1DigestDrift(label: label, recorded: recorded, rebuilt: actual);
      if (drift != null) {
        await refuse('INPUT_PROVENANCE_DRIFT', drift);
      }
    }

    await provenance('JOIN_TABLE_FILE',
        _reqStr(verdictFinal, 'join_table_sha256'),
        await _sha256OfFile(joinTablePath));

    Map<String, Object?>? joinRow;
    for (final r in _reqList(joinTable, 'rows')) {
      final m = (r as Map).cast<String, Object?>();
      if (m['real_id'] == 'a3-plant-1') joinRow = m;
    }
    if (joinRow == null) {
      await refuse(
          'JOIN_ROW_MISSING', 'no real_id=a3-plant-1 row in join-table');
    }
    final arm = _reqStr(joinRow, 'label');
    if (joinRow['certified'] != true) {
      await refuse('ARM_NOT_CERTIFIED',
          'join-table row a3-plant-1 ($arm) is not certified; nothing to replay');
    }
    final joinDigests = _reqMap(joinRow, 'digests');
    final batteryDigest = _reqStr(joinDigests, 'battery_R');

    // per-arm row in A3-run.jsonl (recorded repair_spec digest) + run plan
    String? recordedRepairSpecSha;
    Map<String, Object?>? runPlan;
    for (final line in File(runJsonlPath).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final row = (jsonDecode(line) as Map).cast<String, Object?>();
      final payload = _reqMap(row, 'payload');
      if (row['kind'] == 'a3-run-plan' && runPlan == null) runPlan = payload;
      if (row['kind'] == 'a3-arm' && payload['arm'] == arm) {
        final artifacts = _reqMap(payload, 'artifacts');
        recordedRepairSpecSha =
            _reqStr(_reqMap(artifacts, 'repair_spec.json'), 'sha256');
      }
    }
    if (recordedRepairSpecSha == null) {
      await refuse('RUN_ROW_MISSING', 'no a3-arm row for $arm in A3-run.jsonl');
    }

    await provenance('MIRROR_RECEIPT_FILE',
        _reqStr(joinDigests, 'mirror_receipt'),
        await _sha256OfFile('$armDir/mirror_receipt.json'));
    await provenance('REPAIR_RECEIPT_FILE',
        _reqStr(joinDigests, 'repair_receipt'),
        await _sha256OfFile('$armDir/repair_receipt.json'));
    await provenance('RECOVERED_FILE',
        _reqStr(joinDigests, 'recovered_json'),
        await _sha256OfFile('$armDir/recovered.json'));
    await provenance('REPAIR_SPEC_FILE', recordedRepairSpecSha,
        await _sha256OfFile('$armDir/repair_spec.json'));

    // base snapshot identity
    final recordedM = _reqStr(mirrorReceipt, 'mirror_shard_sha256');
    final baseDigests = _reqMap(mirrorReceipt, 'base_file_digests');
    final baseAbs = Directory(base).absolute.path;
    if (_reqStr(mirrorReceipt, 'base_dir') != baseAbs) {
      await refuse('BASE_PATH_MISMATCH',
          'recorded=${_reqStr(mirrorReceipt, 'base_dir')} given=$baseAbs');
    }
    await provenance('BASE_SHARD',
        _reqStr(baseDigests, 'model.safetensors'),
        await _sha256OfFile('$base/model.safetensors'));

    // repair spec tensors (the recovered removal edit) vs recorded truth
    final repairTensors = <Map<String, Object?>>[
      for (final t in _reqList(repairSpec, 'tensors'))
        (t as Map).cast<String, Object?>(),
    ];
    if (repairTensors.isEmpty) {
      await refuse('REPAIR_SPEC_MALFORMED', 'empty tensors list');
    }
    final repairedRows = <Map<String, Object?>>[
      for (final t in _reqList(repairReceipt, 'repaired'))
        (t as Map).cast<String, Object?>(),
    ];
    final recoveredLayers = _reqMap(recovered, 'layers');

    final layers = <String>[];
    final recordedR = <String, String>{}; // tensor -> post-repair f32 digest
    final truthSpecPathByLayer = <String, String>{};
    for (final t in repairTensors) {
      final name = _reqStr(t, 'name');
      final layer = _layerOf(name);
      layers.add(layer);
      final row = repairedRows.where((r) => r['tensor'] == name).toList();
      if (row.length != 1) {
        await refuse('REPAIR_RECEIPT_ROW_MISSING',
            'tensor=$name rows=${row.length}');
      }
      recordedR[name] = _reqStr(row.single, 'post_repair_tensor_f32_sha256');

      // direction provenance: repair spec direction == proposer output
      final recLayer = _reqMap(recoveredLayers, layer);
      if (!_numsEqual(
          _reqList(t, 'direction'), _reqList(recLayer, 'direction'))) {
        await refuse('DIRECTION_PROVENANCE_DRIFT',
            'repair_spec direction != recovered.json layers[$layer] for $name');
      }
      // plant provenance: same columns, negated scale, recorded spec digest
      final truthPath = '$truthSpecs/spec_L$layer.json';
      final truth = _readJson(truthPath);
      if (!_numsEqual(_reqList(t, 'columns'), _reqList(truth, 'columns'))) {
        await refuse('COLUMNS_PROVENANCE_DRIFT',
            'repair_spec columns != truth spec columns for $name');
      }
      final plantScale = (_req(truth, 'scale')! as num).toDouble();
      final repairScale = (_req(t, 'scale')! as num).toDouble();
      if (repairScale != -plantScale) {
        await refuse('SCALE_PROVENANCE_DRIFT',
            'repair scale=$repairScale != -(plant scale=$plantScale) for $name');
      }
      await provenance('TRUTH_SPEC_L$layer',
          _recordedSpecDigest(mirrorReceipt, name),
          await _sha256OfFile(truthPath));
      // blind arm copy of the spec (the bytes A3's builder consumed)
      await provenance('BLIND_SPEC_L$layer', await _sha256OfFile(truthPath),
          await _sha256OfFile('$armDir/specs/spec_L$layer.json'));
      truthSpecPathByLayer[layer] = truthPath;
    }

    // ---- 2. rebuild the plant mirror M with A3's own builders ----
    final workDir = Directory(work);
    if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    workDir.createSync(recursive: true);

    for (final layer in layers) {
      _runStep('apply_delta_M_L$layer', python, applyDelta, [
        '--base', base,
        '--spec', truthSpecPathByLayer[layer]!,
        '--out', '$work/sidecarsM/L$layer',
      ]);
    }
    _runStep('make_mirror_M', python, makeMirror, [
      '--base', base,
      '--out', '$work/mirrorM',
      for (final layer in layers) ...['--sidecar', '$work/sidecarsM/L$layer'],
      '--receipt', '$work/mirrorM_receipt.json',
    ]);
    final rebuiltMReceipt = _readJson('$work/mirrorM_receipt.json');
    final rebuiltM = _reqStr(rebuiltMReceipt, 'mirror_shard_sha256');
    stdout.writeln('WS1 mirror_M rebuilt shard=$rebuiltM recorded=$recordedM');
    final driftM = ws1DigestDrift(
        label: 'MIRROR_SHARD_M', recorded: recordedM, rebuilt: rebuiltM);
    if (driftM != null) {
      await refuse('REPLAY_DIGEST_DRIFT', driftM,
          step: 'rebuild_M',
          extra: {'file': '$work/mirrorM/model.safetensors'});
    }

    // ---- 3. typed patch + patch_algebra apply on the REAL window ----
    final actualMFingerprint =
        await _sha256OfFile('$work/mirrorM/model.safetensors');
    final canonicalSpecs = <String, Map<String, Object?>>{};
    final patchDigests = <String, String>{};
    final postWindowFingerprints = <String, String>{};
    for (final t in repairTensors) {
      final name = _reqStr(t, 'name');
      final spec = <String, Object?>{
        'tensor': name,
        'columns': [
          for (final c in _reqList(t, 'columns')) (c! as num).toInt(),
        ],
        'direction': [
          for (final d in _reqList(t, 'direction')) (d! as num).toDouble(),
        ],
        'scale': (_req(t, 'scale')! as num).toDouble(),
      };
      final entry = sidecarDeltaToPatch(spec, baseFingerprint: recordedM);
      final canonical = patchToSidecarSpec(entry);
      // round-trip stability (Tolerance.exact): canonical == spec numerically
      if (canonical['tensor'] != spec['tensor'] ||
          !_numsEqual(
              canonical['columns']! as List, spec['columns']! as List) ||
          !_numsEqual(
              canonical['direction']! as List, spec['direction']! as List) ||
          (canonical['scale']! as num) != (spec['scale']! as num)) {
        await refuse('ROUNDTRIP_DRIFT',
            'patchToSidecarSpec(sidecarDeltaToPatch(spec)) != spec for $name');
      }
      canonicalSpecs[name] = canonical;
      patchDigests[name] = patchDigestOf(canonical);

      // The typed patch address carries ABSOLUTE column bounds, so the
      // algebra materializes against the full tensor (no re-addressing).
      final exportOut = _runStep('export_window_$name', python, exportWindow, [
        '--store', '$work/mirrorM',
        '--tensor', name,
        '--out', '$work/window.f64',
      ]);
      final m = RegExp(r'ROWS=(\d+) WIDTH=(\d+)').firstMatch(exportOut);
      if (m == null) {
        throw _Ws1Error('WINDOW_EXPORT_MALFORMED', exportOut,
            step: 'export_window_$name');
      }
      final baseWindow = _readWindowF64('$work/window.f64',
          int.parse(m.group(1)!), int.parse(m.group(2)!));
      final result = apply(baseWindow, entry,
          tol: Tolerance.exact, actualFingerprint: actualMFingerprint);
      if (result is Conflict) {
        await refuse(result.reason.label, result.detail,
            step: 'patch_apply_$name');
      }
      postWindowFingerprints[name] =
          tensorFingerprint((result as Applied).tensor);
      stdout.writeln('WS1 typed patch applied tensor=$name '
          'patch_digest=${patchDigests[name]}');
    }

    // ---- 4. rebuild the removal mirror R via the typed patch ----
    for (final t in repairTensors) {
      final layer = _layerOf(_reqStr(t, 'name'));
      File('$work/spec_R_L$layer.json')
          .writeAsStringSync(jsonEncode(canonicalSpecs[_reqStr(t, 'name')]));
      _runStep('apply_delta_R_L$layer', python, applyDelta, [
        '--base', '$work/mirrorM',
        '--spec', '$work/spec_R_L$layer.json',
        '--out', '$work/sidecarsR/L$layer',
      ]);
    }
    _runStep('make_mirror_R', python, makeMirror, [
      '--base', '$work/mirrorM',
      '--out', '$work/mirrorR',
      for (final layer in layers) ...['--sidecar', '$work/sidecarsR/L$layer'],
      '--receipt', '$work/mirrorR_receipt.json',
    ]);
    final rebuiltRReceipt = _readJson('$work/mirrorR_receipt.json');
    final rebuiltRShard = _reqStr(rebuiltRReceipt, 'mirror_shard_sha256');
    final rebuiltR = <String, String>{};
    for (final e in _reqList(rebuiltRReceipt, 'edited')) {
      final m = (e as Map).cast<String, Object?>();
      rebuiltR[_reqStr(m, 'tensor')] = _reqStr(m, 'mirror_tensor_f32_sha256');
    }
    final driftsR = <String>[];
    for (final t in repairTensors) {
      final name = _reqStr(t, 'name');
      final rebuiltDigest = rebuiltR[name];
      if (rebuiltDigest == null) {
        driftsR.add('REPLAY_DIGEST_DRIFT POST_REPAIR_TENSOR_F32[$name] '
            'recorded=${recordedR[name]} rebuilt=MISSING_IN_REBUILT_RECEIPT');
        continue;
      }
      final d = ws1DigestDrift(
          label: 'POST_REPAIR_TENSOR_F32[$name]',
          recorded: recordedR[name]!,
          rebuilt: rebuiltDigest);
      if (d != null) driftsR.add(d);
      stdout.writeln('WS1 mirror_R tensor=$name rebuilt=$rebuiltDigest '
          'recorded=${recordedR[name]}');
    }
    if (driftsR.isNotEmpty) {
      await refuse('REPLAY_DIGEST_DRIFT', driftsR.join('; '),
          step: 'rebuild_R',
          extra: {'rebuilt_mirror_shard_observed': rebuiltRShard});
    }

    // ---- 5. ledger rows: edit + replay receipts + verdict ----
    final reproducedFlags = <bool>[];
    final replayRows = <Map<String, Object?>>[];
    for (final t in repairTensors) {
      final name = _reqStr(t, 'name');
      final editRow = append(
        outFile,
        ReplayReceipt.editRowKind,
        editRowPayload(
          patch: canonicalSpecs[name]!,
          mirrorDigest: recordedR[name]!,
          batteryDigest: batteryDigest,
        ),
      );
      final receipt =
          ReplayReceipt.replay(editRow, mirrorDigest: rebuiltR[name]!);
      reproducedFlags.add(receipt.reproduced);
      append(outFile, 'replay', <String, Object?>{
        ...receipt.toJson(),
        'ws': 'WS-1',
        'mode': 'live',
        'arm': arm,
        'real_id': 'a3-plant-1',
        'tensor': name,
        'edit_row_digest': editRow.digest,
        'mirror_scope': 'post_repair_tensor_f32_sha256 (A3 repair stage was '
            'in-memory; per-tensor digests are the recorded R commitments)',
        'mirror_shard_M': {'recorded': recordedM, 'rebuilt': rebuiltM},
        'mirror_shard_R_rebuilt_observed': rebuiltRShard,
        'base_fingerprint': recordedM,
        'post_window_fingerprint_observed': postWindowFingerprints[name],
        'battery_digest_source': 'join-table digests.battery_R (file pinned '
            'by A3-verdict-final.join_table_sha256)',
      });
      replayRows.add({'tensor': name, ...receipt.toJson()});
    }

    final verdict = ws1VerdictOf(const [], reproducedFlags);
    final toolsRecorded =
        runPlan == null ? const <String, Object?>{} : _reqMap(runPlan, 'tools_sha256');
    final builderDigests = <String, Object?>{};
    for (final script in [
      'tool/eval/apply_delta.py',
      'tool/runs/make_mirror.py',
      'tool/runs/ws1_export_window.py',
    ]) {
      builderDigests[script] = await _sha256OfFile('$repo/$script');
    }
    append(outFile, 'ws1-verdict', {
      'ws': 'WS-1',
      'mode': 'live',
      'at': DateTime.now().toUtc().toIso8601String(),
      'arm': arm,
      'real_id': 'a3-plant-1',
      'verdict': verdict,
      'reproduced': reproducedFlags.every((r) => r),
      'patch_digests': patchDigests,
      'mirror_M': {
        'scope': 'mirror_shard_sha256',
        'recorded': recordedM,
        'rebuilt': rebuiltM,
      },
      'mirror_R': {
        'scope': 'post_repair_tensor_f32_sha256 per tensor',
        'recorded': recordedR,
        'rebuilt': rebuiltR,
        'rebuilt_shard_observed': rebuiltRShard,
      },
      'battery_digest': batteryDigest,
      'replay_receipts': replayRows,
      'base': {
        'snapshot': baseAbs,
        'model_safetensors_sha256': _reqStr(baseDigests, 'model.safetensors'),
      },
      'builders_current_sha256': builderDigests,
      'builders_runplan_recorded': {
        'apply_delta.py':
            (toolsRecorded['eval_frozen_run_only'] as Map?)?['apply_delta.py'],
        'make_mirror.py': (toolsRecorded['runs'] as Map?)?['make_mirror.py'],
      },
      'builder_note': 'A3-run.jsonl seq0 tools_sha256 predates the pre-plant '
          'instrument fix (seq1 fix_note: a3_battery.py fixed BEFORE any '
          'pilot/plant mirror existed; make_mirror.py first pilot stage '
          'exit=0 pre-plant); the operational equality proof is the '
          'bit-identical rebuild of the recorded mirror digests above.',
      'scratch_law': 'mirrors/windows under $work swept after digests; '
          'durable evidence textual (this ledger)',
      'wall_ms_claim': false,
    });

    final chain = verifyChain(outFile);
    if (chain is! ChainIntact) {
      stderr.writeln('CHAIN_BROKEN: $chain');
      exit(1);
    }
    stdout.writeln('WS1_VERDICT $verdict '
        'reproduced=${reproducedFlags.every((r) => r)} chain=$chain '
        'ledger=${outFile.path}');

    // ---- sweep scratch (probe scratch law) ----
    if (!keepWork) {
      for (final p in ['$work/mirrorM', '$work/mirrorR', '$work/window.f64']) {
        final d = Directory(p);
        if (d.existsSync()) {
          d.deleteSync(recursive: true);
        } else if (File(p).existsSync()) {
          File(p).deleteSync();
        }
      }
      stdout.writeln('WS1 swept mirrors/windows under $work '
          '(textual receipts kept)');
    }
  } on _Ws1Error catch (e) {
    await refuse(e.code, e.detail, step: e.step);
  } on ArgumentError catch (e) {
    // bridge/algebra named refusals (SPEC_SHAPE_MISMATCH, SIDECAR_*, ...)
    await refuse('ARGUMENT_REFUSAL',
        '${e.message ?? ''} ${e.invalidValue ?? ''}'.trim());
  }
}
