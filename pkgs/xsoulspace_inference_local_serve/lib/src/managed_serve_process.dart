import 'dart:io' show Process, ProcessSignal;

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

Future<ManagedServeProcess> ioStart(
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
