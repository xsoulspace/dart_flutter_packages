import 'dart:async';

import 'package:http/http.dart' as http;

import 'managed_serve_process.dart';

/// Local, non-probing readiness for a loopback serve runtime.
enum LocalServeState { detached, starting, ready, unavailable, stopped }

/// The shape of one runtime diagnostic event. Events carry configuration
/// and outcome facts only — never prompt text, memory records, or model
/// output — so observers can never become a content side channel.
typedef LocalServeDiagnostic = void Function(Map<String, Object?> event);

/// Composition root for a local model server on this machine.
///
/// The runtime owns exactly one concern: is a server answering on
/// [healthEndpoint]? It can **attach** to an already-running server
/// (the default) or, when [spawnOnMiss] is opted into, start the configured
/// [executable] and wait for health. It never installs anything, never
/// downloads checkpoints, and kills only processes it spawned itself.
///
/// All getters are local snapshots and perform no I/O; [ensureRunning] is
/// the only asynchronous readiness operation. Request-level deadlines are a
/// wire-adapter concern (each client carries its own timeout); this runtime
/// owns the health deadline only.
///
/// This is the shared skeleton extracted from the laya serve runtime, so a
/// second local provider (text generation) composes the same health,
/// deadline, and diagnostics machinery instead of forking it.
final class LocalServeRuntime {
  LocalServeRuntime({
    required this.healthEndpoint,
    required this.executable,
    this.label = 'local-serve',
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.spawnOnMiss = false,
    this.healthTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 200),
    this.onDiagnosticEvent,
    http.Client? httpClient,
    this.processStarter = ioStart,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri healthEndpoint;
  final String executable;

  /// Human-readable server name for honest status messages
  /// (`no laya-serve answering at ...`).
  final String label;
  final List<String> arguments;
  final Map<String, String> environment;

  /// When false (default) a health miss leaves the runtime `unavailable`;
  /// spawning a process is an explicit composition-root decision.
  final bool spawnOnMiss;
  final Duration healthTimeout;
  final Duration pollInterval;

  /// Optional diagnostic observer. Observer errors are ignored so
  /// diagnostics can never change readiness behavior.
  final LocalServeDiagnostic? onDiagnosticEvent;

  final http.Client _httpClient;
  final bool _ownsHttpClient;

  /// The spawn function, injectable for tests.
  final ServeProcessStarter processStarter;

  LocalServeState _state = LocalServeState.detached;
  ManagedServeProcess? _spawned;
  String? _unavailableReason;

  /// Local readiness snapshot. Never performs I/O.
  (LocalServeState, String? reason) get status => (_state, _unavailableReason);

  bool get isReady => _state == LocalServeState.ready;

  /// The spawned process, when this runtime started one. Exposed so a
  /// benchmark or supervisor can read its footprint (RSS) without owning
  /// the lifecycle.
  ManagedServeProcess? get spawnedProcess => _spawned;

  /// Checks [healthEndpoint]; when it misses and [spawnOnMiss] is set,
  /// starts [executable] and polls until healthy or [healthTimeout].
  ///
  /// Returns true when the runtime ends up ready. A failed spawn is recorded
  /// in [status] and is not retried by this call.
  Future<bool> ensureRunning() async {
    if (await _probe()) {
      _state = LocalServeState.ready;
      _unavailableReason = null;
      _emit('local_serve.ready', <String, Object?>{
        'endpoint': '$healthEndpoint',
      });
      return true;
    }
    if (!spawnOnMiss) {
      _state = LocalServeState.unavailable;
      _unavailableReason = 'no $label answering at $healthEndpoint';
      _emit(
        'local_serve.unavailable',
        <String, Object?>{'reason': _unavailableReason},
      );
      return false;
    }
    _state = LocalServeState.starting;
    try {
      _spawned = await _processStarter(executable, arguments, environment);
    } on Object catch (error) {
      _state = LocalServeState.unavailable;
      _unavailableReason = 'failed to start $executable: $error';
      _emit(
        'local_serve.spawn_failed',
        <String, Object?>{'executable': executable, 'error': '$error'},
      );
      return false;
    }
    _emit(
      'local_serve.spawn',
      <String, Object?>{'executable': executable, 'pid': _spawned!.pid},
    );
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
          _state = LocalServeState.unavailable;
          _unavailableReason = '$executable exited before becoming healthy';
          _emit(
            'local_serve.exit_before_ready',
            <String, Object?>{'executable': executable},
          );
          return false;
        }
      }
      if (await _probe()) {
        _state = LocalServeState.ready;
        _unavailableReason = null;
        _emit('local_serve.ready', <String, Object?>{
          'endpoint': '$healthEndpoint',
        });
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    _state = LocalServeState.unavailable;
    _unavailableReason =
        '$executable did not become healthy within '
        '${healthTimeout.inMilliseconds}ms';
    _emit(
      'local_serve.unavailable',
      <String, Object?>{'reason': _unavailableReason},
    );
    return false;
  }

  /// Kills the spawned process, if this runtime started one, and resets the
  /// readiness snapshot. Attached (external) servers are left running.
  Future<void> stop() async {
    final spawned = _spawned;
    _spawned = null;
    spawned?.kill();
    _state = LocalServeState.stopped;
    _unavailableReason = null;
    _emit(
      'local_serve.stopped',
      <String, Object?>{'killed_spawned': spawned != null},
    );
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
      // details); any answering status below 500 counts as alive. A 404
      // from a server without a health route still proves the socket —
      // and therefore the process — is up.
      final ok = response.statusCode >= 200 && response.statusCode < 500;
      _emit(
        'local_serve.health_probe',
        <String, Object?>{'endpoint': '$healthEndpoint', 'ok': ok},
      );
      return ok;
    } on Object {
      _emit(
        'local_serve.health_probe',
        <String, Object?>{'endpoint': '$healthEndpoint', 'ok': false},
      );
      return false;
    }
  }

  void _emit(final String type, final Map<String, Object?> fields) {
    try {
      onDiagnosticEvent?.call(<String, Object?>{'type': type, ...fields});
    } on Object {
      // Diagnostics must never change readiness behavior.
    }
  }
}
