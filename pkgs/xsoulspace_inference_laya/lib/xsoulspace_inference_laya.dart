library;

// R3 (ADR 0057, executed 2026-10-09): the engine re-export shim is
// DROPPED. Import engine symbols from the engine package directly:
//
//   import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';
//
// This package keeps only the laya product surface: the local serve
// runtime composition and the DecisionProvider bound to it.

// The laya product surface: the local serve runtime composition and the
// DecisionProvider bound to it.
export 'src/laya_local_decision_provider.dart';
export 'src/laya_serve_runtime.dart';
