library;

// R2 shim (ADR 0057): the engine host (the Rust cdylib, the composition
// API, the model drivers with their FFI clients and chat servers, and the
// decision seam they serve) moved to `xsoulspace_inference_mlx_native`.
// This re-export keeps harness consumers (afm, experiments) compiling
// UNCHANGED for one deprecation cycle; R3 drops this shim — import the
// engine package directly for engine symbols.
export 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

// The laya product surface: the local serve runtime composition and the
// DecisionProvider bound to it.
export 'src/laya_local_decision_provider.dart';
export 'src/laya_serve_runtime.dart';
