import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

export 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart'
    show LocalServeDiagnostic, LocalServeState, ManagedServeProcess;

/// Local, non-probing readiness for the MLX serve runtime (shared states).
typedef MlxRuntimeState = LocalServeState;

/// Spawn arguments for `mlx_lm.server` (the documented Liquid AI MLX
/// deployment shape): a local model path or Hugging Face repo id, bound to
/// the loopback interface only.
final class MlxServeArguments {
  const MlxServeArguments._();

  /// `--model <model> --host <host> --port <port>`.
  static List<String> command({
    required final String model,
    final String host = '127.0.0.1',
    final int port = MlxServeRuntime.defaultPort,
  }) => <String>['--model', model, '--host', host, '--port', '$port'];
}

/// Composition root for a local MLX text-model server on this machine.
///
/// The same health-gated, attach-only-or-spawnOnMiss skeleton the laya
/// runtime composes, with MLX defaults: the server answers OpenAI-compatible
/// chat on [defaultEndpoint], health is the same endpoint's `/health` (a
/// 404 from a server without that route still proves the socket — and the
/// server binds only after the model has loaded, so "answering" means
/// "ready to generate").
///
/// It never installs anything, never downloads checkpoints, and kills only
/// processes it spawned itself. All getters are local snapshots and perform
/// no I/O; [ensureRunning] is the only asynchronous readiness operation.
final class MlxServeRuntime {
  /// The default loopback port (laya owns 8000; MLX binds beside it).
  static const int defaultPort = 8765;

  static Uri defaultEndpoint() => Uri.parse('http://127.0.0.1:$defaultPort');

  MlxServeRuntime({
    final Uri? healthEndpoint,
    this.executable = 'mlx_lm.server',
    final List<String> arguments = const <String>[],
    final Map<String, String> environment = const <String, String>{},
    this.spawnOnMiss = false,
    // Model load on an M1-class machine takes tens of seconds; the health
    // deadline must cover a cold load, not just a socket wait.
    this.healthTimeout = const Duration(seconds: 120),
    this.pollInterval = const Duration(milliseconds: 250),
    final void Function(Map<String, Object?> event)? onDiagnosticEvent,
    http.Client? httpClient,
    ServeProcessStarter processStarter = ioStart,
  }) : _runtime = LocalServeRuntime(
         healthEndpoint:
             healthEndpoint ?? defaultEndpoint().replace(path: '/health'),
         executable: executable,
         label: 'mlx-lm server',
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

  Uri get healthEndpoint => _runtime.healthEndpoint;

  /// The base URL the server answers on, derived from [healthEndpoint] by
  /// stripping the `/health` suffix. The text client derives its chat URL
  /// from this, so ONE endpoint configuration drives both readiness and
  /// dispatch (a lane that points the runtime at a fixture server must
  /// never chat with the default port).
  Uri get endpoint {
    final health = _runtime.healthEndpoint;
    final path = health.path;
    return path.endsWith('/health')
        ? health.replace(
            path: path.substring(0, path.length - '/health'.length),
          )
        : health;
  }

  List<String> get arguments => _runtime.arguments;
  Map<String, String> get environment => _runtime.environment;

  /// Local readiness snapshot. Never performs I/O.
  (MlxRuntimeState, String? reason) get status => _runtime.status;

  bool get isReady => _runtime.isReady;

  /// The spawned server process, when this runtime started one — the
  /// footprint (RSS) a benchmark records.
  ManagedServeProcess? get spawnedProcess => _runtime.spawnedProcess;

  /// Checks health; when it misses and [spawnOnMiss] is set, starts
  /// [executable] and polls until healthy or [healthTimeout].
  Future<bool> ensureRunning() => _runtime.ensureRunning();

  /// Kills the spawned process, if this runtime started one. Attached
  /// (external) servers are left running.
  Future<void> stop() => _runtime.stop();

  Future<void> dispose() => _runtime.dispose();
}

/// Decision-provider-shaped readiness facts are laya's surface; the MLX
/// text client reports its availability through [InferenceClient] instead.
/// This probe exists for lane scripts that only want a one-shot answer.
typedef MlxHealthProbe = LocalHealthProbe;
