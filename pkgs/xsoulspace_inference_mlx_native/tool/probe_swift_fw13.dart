import 'dart:convert';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:ffi';
import 'dart:io';

/// ADR 0051 diagnostic: drives the HISTORICAL Swift dylib directly (plain
/// FFI lookups, no native-assets) on inputs dumped from the Rust engine's
/// forward, to attribute golden disagreements.
void main(List<String> args) {
  final dylibPath = args[0];
  final dumpDir = args[1];
  final lib = DynamicLibrary.open(dylibPath);

  final load = lib
      .lookupFunction<Int Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>(
          'laya_native_load');
  final forward = lib
      .lookupFunction<Pointer<Uint8> Function(Int64, Pointer<Uint8>),
          Pointer<Uint8> Function(int, Pointer<Uint8>)>('laya_native_forward');
  final free = lib
      .lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
          'laya_native_free');

  Pointer<Uint8> toNative(String s) {
    final bytes = utf8.encode(s);
    final p = malloc<Uint8>(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      p[i] = bytes[i];
    }
    p[bytes.length] = 0;
    return p;
  }

  List<double> readBin(String name) {
    final meta =
        jsonDecode(File('$dumpDir/fw13_$name.json').readAsStringSync()) as Map;
    final bytes = File('$dumpDir/${meta['file']}').readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    return List.generate(bytes.length ~/ 4, (i) => data.getFloat32(i * 4, Endian.little));
  }

  final ids = readBin('in_ids').map((v) => v.round()).toList();
  // masks are part of the dumped batch but the request rebuilt here carries
  // per-row ids only; the engine rebuilds masks from ids lengths.
  final mpos = readBin('in_marker_pos').map((v) => v.round()).toList();
  final mmask = readBin('in_marker_mask').map((v) => v.round()).toList();
  final qtypes = readBin('in_qtype').map((v) => v.round()).toList();
  final shape = (jsonDecode(File('$dumpDir/fw13_in_ids.json').readAsStringSync())
      as Map)['shape'] as List;
  final b = shape[0] as int;
  final l = shape[1] as int;
  final k = ((jsonDecode(File('$dumpDir/fw13_in_marker_mask.json').readAsStringSync())
          as Map)['shape'] as List)[1] as int;

  final handle = load(toNative(Platform.environment['LAYA_MODEL_DIR'] ??
      '${Platform.environment['HOME']}/.cache/xsoulspace/laya-mlx'));
  if (handle <= 0) {
    stderr.writeln('swift load failed: $handle');
    exit(1);
  }
  final batch = [
    for (var r = 0; r < b; r++)
      {
        'ids': ids.sublist(r * l, (r + 1) * l),
        'markers': [
          for (var c = 0; c < k; c++)
            if (mmask[r * k + c] == 1) mpos[r * k + c],
        ],
        'qtype': qtypes[r],
      },
  ];
  final request = jsonEncode({'batch': batch});
  final reqNative = toNative(request);
  // warmup + timed forwards (raw FFI, no tokenization)
  for (var i = 0; i < 3; i++) {
    free(forward(handle, reqNative));
  }
  final sw = Stopwatch()..start();
  const iters = 10;
  for (var i = 0; i < iters; i++) {
    free(forward(handle, reqNative));
  }
  sw.stop();
  // ignore: avoid_print
  print('raw forward (B=$b, L=$l): ${sw.elapsedMicroseconds / iters / 1000} ms/iter');
  final responseNative = forward(handle, reqNative);
  final responseBytes = <int>[];
  var i = 0;
  while (true) {
    final byte = responseNative[i];
    if (byte == 0) break;
    responseBytes.add(byte);
    i++;
  }
  final response = jsonDecode(utf8.decode(responseBytes)) as Map;
  if (response['error'] is String) {
    stderr.writeln('swift forward error: ${response['error']}');
    exit(1);
  }
  final logits = (response['logits'] as List)
      .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
      .toList();
  for (final r in [0, 9, 12]) {
    // ignore: avoid_print
    print('swift row $r: ${logits[r].map((v) => v.toStringAsFixed(2)).toList()}');
  }
  final engineLogits = readBin('logits');
  var maxDiff = 0.0;
  for (var r = 0; r < b; r++) {
    for (var c = 0; c < k; c++) {
      final e = engineLogits[r * k + c];
      final s = logits[r][c];
      if (e > -9000 && s > -9000) maxDiff = (e - s).abs() > maxDiff ? (e - s).abs() : maxDiff;
    }
  }
  // ignore: avoid_print
  print('swift-vs-rust max abs logit diff (valid entries): $maxDiff');
}
