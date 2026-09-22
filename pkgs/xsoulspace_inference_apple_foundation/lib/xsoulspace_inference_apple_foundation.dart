/// Apple Foundation Models (SystemLanguageModel) backend for
/// `xsoulspace_inference_core` via a pure-Dart FFI bridge (macOS 26+).
///
/// This package owns the FFI transport (`AppleFoundationNativeClient`) and
/// the native-asset build. The harness daemon and the AFM composition root
/// live in the `ecsai_harness` product (`xsoulspace_agentic_afm`), which
/// depends on this client. This package does not depend on the harness.
library;

// The native FFI bridge only exists where dart:ffi does. On the web target
// the barrel binds the honest web stub instead (`isAvailable` is false,
// `infer` fails with the named code `engine_unavailable`). NOTE:
// `dart.library.io` is TRUE on Flutter web (the SDK ships a stub dart:io),
// so web is detected via `dart.library.js_interop`.
export 'src/native_bridge/native_client.dart'
    if (dart.library.js_interop) 'src/native_bridge/native_client_web.dart';
