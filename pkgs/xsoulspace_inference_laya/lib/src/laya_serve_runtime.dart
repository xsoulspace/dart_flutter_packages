import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

export 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart'
    show
        IoManagedServeProcess,
        LocalHealthProbe,
        LocalServeState,
        LocalServeDiagnostic,
        LoopbackJsonServer,
        LoopbackReply,
        LoopbackRequest,
        LoopbackRoute,
        ManagedServeProcess,
        ServeProcessStarter,
        ioStart;

/// Local, non-probing readiness for the laya-serve runtime. The states live
/// in the shared local-serve core; this alias keeps the laya spelling.
typedef LayaRuntimeState = LocalServeState;

/// Composition root for a local [Laya](https://huggingface.co/convaiinnovations/laya)
/// decision server (`laya-serve`) on this machine.
///
/// The runtime owns exactly one concern: is a laya-serve endpoint answering
/// on [healthEndpoint]? It can **attach** to an already-running server
/// (the default) or, when [spawnOnMiss] is opted into, start the configured
/// [executable] and wait for health. It never installs anything, never
/// downloads checkpoints, and kills only processes it spawned itself.
///
/// All getters are local snapshots and perform no I/O; [ensureRunning] is
/// the only asynchronous readiness operation.
///
/// The health, deadline, diagnostics, and process machinery is the shared
/// local-serve core (`xsoulspace_inference_local_serve`); this class is the
/// laya-shaped composition of it — defaults, label, and the public surface
/// the harness binding composes.
final class LayaServeRuntime {
  LayaServeRuntime({
    final Uri? healthEndpoint,
    this.executable = 'laya-serve',
    final List<String> arguments = const <String>[],
    final Map<String, String> environment = const <String, String>{},
    this.spawnOnMiss = false,
    this.healthTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 200),
    final void Function(Map<String, Object?> event)? onDiagnosticEvent,
    http.Client? httpClient,
    ServeProcessStarter processStarter = ioStart,
  }) : _runtime = LocalServeRuntime(
         healthEndpoint:
             healthEndpoint ?? Uri.parse('http://127.0.0.1:8000/health'),
         executable: executable,
         label: 'laya-serve',
         arguments: arguments,
         environment: environment,
         spawnOnMiss: spawnOnMiss,
         healthTimeout: healthTimeout,
         pollInterval: pollInterval,
         onDiagnosticEvent: onDiagnosticEvent,
         httpClient: httpClient,
         processStarter: processStarter,
       );

  final String executable;
  final bool spawnOnMiss;
  final Duration healthTimeout;
  final Duration pollInterval;

  final LocalServeRuntime _runtime;

  /// The laya defaults live in the constructor; these fields stay for
  /// introspection by hosts that render configuration.
  Uri get healthEndpoint => _runtime.healthEndpoint;
  List<String> get arguments => _runtime.arguments;
  Map<String, String> get environment => _runtime.environment;

  /// Local readiness snapshot. Never performs I/O.
  (LayaRuntimeState, String? reason) get status => _runtime.status;

  bool get isReady => _runtime.isReady;

  /// The spawned process, when this runtime started one.
  ManagedServeProcess? get spawnedProcess => _runtime.spawnedProcess;

  /// Checks [healthEndpoint]; when it misses and [spawnOnMiss] is set,
  /// starts [executable] and polls until healthy or [healthTimeout].
  ///
  /// Returns true when the runtime ends up ready. A failed spawn is recorded
  /// in [status] and is not retried by this call.
  Future<bool> ensureRunning() => _runtime.ensureRunning();

  /// Kills the spawned process, if this runtime started one, and resets the
  /// readiness snapshot. Attached (external) servers are left running.
  Future<void> stop() => _runtime.stop();

  Future<void> dispose() => _runtime.dispose();
}
