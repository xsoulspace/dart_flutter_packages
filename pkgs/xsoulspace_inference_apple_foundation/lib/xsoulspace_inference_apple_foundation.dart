/// Apple Foundation Models (SystemLanguageModel) backend for
/// `xsoulspace_inference_core` via a pure-Dart FFI bridge (macOS 26+).
///
/// Provider-THIN (ADR 0025): this package owns only the FFI transport
/// (`AppleFoundationNativeClient`), the native-asset build, and the
/// `harnessd` composition root (`bin/harnessd.dart`). The daemon, the
/// coding runner and the ACP host policy live in
/// `package:xsoulspace_agentic_host` — apps (last_answer), CLIs and pi
/// extensions embed THAT surface and inject this package's client as a
/// `HarnessBackendBinding`.
library;

import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'src/native_bridge/native_client.dart';

export 'src/native_bridge/native_client.dart';

/// The `apple_foundation_afm` backend binding (ADR 0025) — the one-liner
/// an app, CLI or test composes to embed AFM in the harnessd daemon:
///
/// ```dart
/// final afm = appleFoundationBinding();
/// final backend = HarnessAcpBackend(
///   backend: 'apple_foundation_afm',
///   bindings: {'apple_foundation_afm': afm.binding},
/// );
/// // ...; later: afm.client?.cancelActiveGeneration();
/// ```
///
/// The client is RETAINED and LAZY ([AppleFoundationClientBinding.client])
/// so session cancel can reach `xs_fm_cancel`, while scripted /
/// handler-factory modes never materialize the dylib.
AppleFoundationClientBinding appleFoundationBinding() {
  AppleFoundationNativeClient? client;
  ModelRouter? router;
  final binding = HarnessBackendBinding(
    defaultModel: DefaultModelNames.appleFoundation.name,
    buildRouter: ({required model, apiKey}) {
      final c = client ??= AppleFoundationNativeClient();
      return router ??= ModelRouter(
        inferenceClientsBuilders: {
          DefaultModelNames.appleFoundation: () => client!,
        },
      )
        ..models[const ModelId('harnessd')] = Model(
          id: const ModelId('harnessd'),
          name: DefaultModelNames.appleFoundation,
        );
    },
    cancelActiveGeneration: () => client?.cancelActiveGeneration(),
  );
  return AppleFoundationClientBinding(
    binding: binding,
    client: () => client,
  );
}

/// The retained AFM client + the host binding, returned together so an
/// embedded host can also reach the client directly (e.g. streaming
/// smoke, cancellation, health probes).
class AppleFoundationClientBinding {
  const AppleFoundationClientBinding({
    required this.binding,
    required this.client,
  });

  /// The host-layer binding to register in `HarnessAcpBackend.bindings`.
  final HarnessBackendBinding binding;

  /// The retained native client (FFI transport) — null until the binding's
  /// router has been used (lazy materialization).
  final AppleFoundationNativeClient? Function() client;
}
