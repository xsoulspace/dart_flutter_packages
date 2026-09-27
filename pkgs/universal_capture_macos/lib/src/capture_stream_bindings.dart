import 'dart:ffi';

/// Streaming bindings. The callback is a Dart `NativeCallable.listener`
/// handed to the bridge as a native function pointer; frame bytes are
/// only valid for the duration of the call, so the Dart side copies
/// them immediately.
typedef XsStreamFrameCallbackNative = Void Function(
  Pointer<Uint8> bytes,
  Int32 length,
  Int64 timestampUs,
  Pointer<Void> userData,
);

@Native<Int32 Function(Uint32, Int32,
    Pointer<NativeFunction<XsStreamFrameCallbackNative>>, Pointer<Void>)>(
  symbol: 'xs_capture_stream_start',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external int streamStartNative(
  int displayId,
  int maxFps,
  Pointer<NativeFunction<XsStreamFrameCallbackNative>> callback,
  Pointer<Void> userData,
);

@Native<Int32 Function(Int32)>(
  symbol: 'xs_capture_stream_stop',
  assetId: 'package:universal_capture_macos/xs_capture_bridge',
)
external int streamStopNative(int handle);
