import 'dart:async';
import 'dart:io' show Process, ProcessSignal;

import 'package:http/http.dart' as http;

/// A spawned server process handle, abstracted so tests can fake the
/// lifecycle without real processes.
abstract interface class ManagedServeProcess {
  int get pid;

  void kill();

  Future<void> get done;
}

final class IoManagedServeProcess implements ManagedServeProcess {
  IoManagedServeProcess(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  void kill() => _process.kill(ProcessSignal.sigterm);

  @override
  Future<void> get done => _process.exitCode;
}

/// Spawns the server process. Injectable for tests.
typedef ServeProcessStarter =
    Future<ManagedServeProcess> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    );

Future<ManagedServeProcess> _ioStart(
  final String executable,
  final List<String> arguments,
  final Map<String, String> environment,
) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
  );
  return IoManagedServeProcess(process);
}

/// Local, non-probing readiness for the laya-serve runtime.
enum LayaRuntimeState { detached, starting, ready, unavailable, stopped }

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
final class LayaServeRuntime {
  LayaServeRuntime({
    final Uri? healthEndpoint,
    this.executable = 'laya-serve',
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.spawnOnMiss = false,
    this.healthTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 200),
    http.Client? httpClient,
    ServeProcessStarter processStarter = _ioStart,
  }) : healthEndpoint =
           healthEndpoint ?? Uri.parse('http://127.0.0.1:8000/health'),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       // A named parameter cannot spell the private initializing formal.
       // ignore: prefer_initializing_formals
       _processStarter = processStarter;

  final Uri healthEndpoint;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;

  /// When false (default) a health miss leaves the runtime `unavailable`;
  /// spawning a process is an explicit composition-root decision.
  final bool spawnOnMiss;
  final Duration healthTimeout;
  final Duration pollInterval;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final ServeProcessStarter _processStarter;

  LayaRuntimeState _state = LayaRuntimeState.detached;
  ManagedServeProcess? _spawned;
  String? _unavailableReason;

  /// Local readiness snapshot. Never performs I/O.
  (LayaRuntimeState, String? reason) get status => (_state, _unavailableReason);

  bool get isReady => _state == LayaRuntimeState.ready;

  /// Checks [healthEndpoint]; when it misses and [spawnOnMiss] is set,
  /// starts [executable] and polls until healthy or [healthTimeout].
  ///
  /// Returns true when the runtime ends up ready. A failed spawn is recorded
  /// in [status] and is not retried by this call.
  Future<bool> ensureRunning() async {
    if (await _probe()) {
      _state = LayaRuntimeState.ready;
      _unavailableReason = null;
      return true;
    }
    if (!spawnOnMiss) {
      _state = LayaRuntimeState.unavailable;
      _unavailableReason = 'no laya-serve answering at $healthEndpoint';
      return false;
    }
    _state = LayaRuntimeState.starting;
    try {
      _spawned = await _processStarter(executable, arguments, environment);
    } on Object catch (error) {
      _state = LayaRuntimeState.unavailable;
      _unavailableReason = 'failed to start $executable: $error';
      return false;
    }
    final deadline = DateTime.now().add(healthTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_spawned != null) {
        // Surface an early exit instead of polling a dead process for the
        // full budget. When the process already exited, its future completes
        // as a microtask and wins the race against the zero-duration timer;
        // when it is still running, the timer does.
        final exited = await Future.any<bool>(<Future<bool>>[
          _spawned!.done.then((_) => true),
          Future<bool>.delayed(Duration.zero, () => false),
        ]);
        if (exited) {
          _state = LayaRuntimeState.unavailable;
          _unavailableReason = '$executable exited before becoming healthy';
          return false;
        }
      }
      if (await _probe()) {
        _state = LayaRuntimeState.ready;
        _unavailableReason = null;
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    _state = LayaRuntimeState.unavailable;
    _unavailableReason =
        '$executable did not become healthy within '
        '${healthTimeout.inMilliseconds}ms';
    return false;
  }

  /// Kills the spawned process, if this runtime started one, and resets the
  /// readiness snapshot. Attached (external) servers are left running.
  Future<void> stop() async {
    final spawned = _spawned;
    _spawned = null;
    spawned?.kill();
    _state = LayaRuntimeState.stopped;
    _unavailableReason = null;
  }

  Future<void> dispose() async {
    await stop();
    if (_ownsHttpClient) _httpClient.close();
  }

  Future<bool> _probe() async {
    try {
      final response = await _httpClient
          .get(healthEndpoint)
          .timeout(
            pollInterval < const Duration(seconds: 2)
                ? const Duration(seconds: 2)
                : pollInterval * 2,
          );
      // /health stays open on the wire (auth only guards deployment
      // details); any answering status below 500 counts as alive.
      return response.statusCode >= 200 && response.statusCode < 500;
    } on Object {
      return false;
    }
  }
}
