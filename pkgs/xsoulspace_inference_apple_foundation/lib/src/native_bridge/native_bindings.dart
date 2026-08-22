/// `@Native` bindings for the Apple Foundation bridge.
///
/// Symbols resolve through the code asset registered by `hook/build.dart`
/// (asset ID = this library's URI). When code assets are unavailable — e.g.
/// Flutter under Dart 3.13, or a dylib built outside the hook — the loader in
/// `library_loader.dart` falls back to `DynamicLibrary.open`.
library;

import 'dart:ffi';

// ignore: library_annotations

@Native<Int32 Function()>(
  assetId: 'package:xsoulspace_inference_apple_foundation/swift_bridge',
)
external int xs_fm_is_available();

@Native<
  Int32 Function(
    Pointer<Char>,
    Pointer<NativeFunction<Void Function(Pointer<Char>)>>,
    Pointer<NativeFunction<Void Function(Pointer<Char>)>>,
  )
>(assetId: 'package:xsoulspace_inference_apple_foundation/swift_bridge')
external int xs_fm_generate_async(
  Pointer<Char> requestJson,
  Pointer<NativeFunction<Void Function(Pointer<Char>)>> toolCb,
  Pointer<NativeFunction<Void Function(Pointer<Char>)>> doneCb,
);

@Native<Int32 Function(Pointer<Char>, Pointer<Char>)>(
  assetId: 'package:xsoulspace_inference_apple_foundation/swift_bridge',
)
external int xs_fm_tool_respond(Pointer<Char> id, Pointer<Char> resultJson);

@Native<Void Function(Pointer<Char>)>(
  assetId: 'package:xsoulspace_inference_apple_foundation/swift_bridge',
)
external void xs_fm_free_string(Pointer<Char> s);
