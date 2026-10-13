/// Native-asset preparation/identity diagnostic. No model or weights load.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:xsoulspace_inference_mlx_native/src/laya_native_decision_engine.dart';

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32)>(
  symbol: 'mlx_native_normalize',
  assetId: 'package:xsoulspace_inference_mlx_native/mlx_native',
)
external int _normalizeAddress(
  Pointer<Uint8> src,
  Pointer<Uint8> out,
  int capacity,
);

final class _DlInfo extends Struct {
  external Pointer<Utf8> filename;
  external Pointer<Void> base;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}

Map<String, Object?> inspectNativeRuntimeIdentity() {
  if (!Platform.isMacOS) throw StateError('native_preflight_requires_macos');
  // This existing binding resolves the code asset and performs harmless NFC.
  final normalized = nfcNormalize('e\u0301');
  if (normalized != 'é') throw StateError('native_preflight_normalize_failed');
  final info = calloc<_DlInfo>();
  try {
    final dladdr = DynamicLibrary.process()
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<_DlInfo>),
          int Function(Pointer<Void>, Pointer<_DlInfo>)
        >('dladdr');
    final address =
        Native.addressOf<
          NativeFunction<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32)>
        >(_normalizeAddress);
    if (dladdr(address.cast<Void>(), info) == 0) {
      throw StateError('native_preflight_image_identity_unavailable');
    }
    final path = File(
      info.ref.filename.toDartString(),
    ).resolveSymbolicLinksSync();
    final metal = File('${File(path).parent.path}/mlx.metallib');
    return {
      'schema': 'mlx_native.preflight.v1',
      'sdk': Platform.version,
      'executable': File(
        Platform.resolvedExecutable,
      ).resolveSymbolicLinksSync(),
      'nativeImage': path,
      'nativeImageBytes': File(path).lengthSync(),
      'colocatedMetal': metal.path,
      'colocatedMetalExists': metal.existsSync(),
      'colocatedMetalBytes': metal.existsSync() ? metal.lengthSync() : null,
      'nfcControl': true,
    };
  } finally {
    calloc.free(info);
  }
}

void main() {
  final identity = inspectNativeRuntimeIdentity();
  stdout.writeln(
    jsonEncode({...identity, 'weightsLoaded': false, 'modelDispatched': false}),
  );
  if (identity['colocatedMetalExists'] != true) exitCode = 2;
}
