import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

void main() {
  group('LocalServeRuntime', () {
    test('attach mode: healthy server flips readiness without spawning',
        () async {
      var spawns = 0;
      final events = <Map<String, Object?>>[];
      final runtime = LocalServeRuntime(
        healthEndpoint: Uri.parse('http://127.0.0.1:8000/health'),
        executable: 'some-serve',
        label: 'some-serve',
        onDiagnosticEvent: events.add,
        httpClient: MockClient((_) async => http.Response('ok', 200)),
        processStarter: (_, _, _) async {
          spawns++;
          throw StateError('must not spawn in attach mode');
        },
      );

      expect(await runtime.ensureRunning(), isTrue);
      expect(runtime.isReady, isTrue);
      expect(runtime.status.$1, LocalServeState.ready);
      expect(spawns, 0);
      expect(
        events.any(
          (e) => e['type'] == 'local_serve.ready' && e['pid'] == null,
        ),
        isTrue,
      );
      await runtime.dispose();
    });

    test('attach mode: health miss records unavailable, no process', () async {
      final runtime = LocalServeRuntime(
        healthEndpoint: Uri.parse('http://127.0.0.1:8000/health'),
        executable: 'some-serve',
        label: 'some-serve',
        httpClient: MockClient(
          (_) async => throw StateError('connection refused'),
        ),
      );

      expect(await runtime.ensureRunning(), isFalse);
      expect(runtime.status.$1, LocalServeState.unavailable);
      expect(runtime.status.$2, contains('no some-serve answering'));
      await runtime.dispose();
    });

    test('spawn mode: starts the process and waits for health', () async {
      var healthy = false;
      ManagedServeProcess? spawned;
      final runtime = LocalServeRuntime(
        healthEndpoint: Uri.parse('http://127.0.0.1:8000/health'),
        executable: 'some-serve',
        spawnOnMiss: true,
        pollInterval: const Duration(milliseconds: 5),
        healthTimeout: const Duration(seconds: 2),
        httpClient: MockClient(
          (_) async =>
              healthy ? http.Response('ok', 200) : throw StateError('refused'),
        ),
        processStarter: (executable, arguments, environment) async {
          expect(executable, 'some-serve');
          return spawned = _FakeProcess();
        },
      );

      final ensure = runtime.ensureRunning();
      // Flip health shortly after spawn so the poll loop observes both
      // sides deterministically.
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        healthy = true;
      });
      unawaited(ensure);

      // Wait for readiness with a bounded loop.
      for (var i = 0; i < 200 && !runtime.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(runtime.isReady, isTrue);
      expect(spawned, isNotNull);
      expect(runtime.spawnedProcess, same(spawned));
      await runtime.dispose();
    });

    test('spawn mode: early process exit fails fast', () async {
      final process = _FakeProcess()..exit();
      final runtime = LocalServeRuntime(
        healthEndpoint: Uri.parse('http://127.0.0.1:8000/health'),
        executable: 'some-serve',
        spawnOnMiss: true,
        pollInterval: const Duration(milliseconds: 5),
        healthTimeout: const Duration(seconds: 5),
        httpClient: MockClient((_) async => throw StateError('refused')),
        processStarter: (_, _, _) async => process,
      );

      expect(await runtime.ensureRunning(), isFalse);
      expect(runtime.status.$1, LocalServeState.unavailable);
      expect(runtime.status.$2, contains('exited before becoming healthy'));
      await runtime.dispose();
    });

    test('stop kills only the spawned process', () async {
      final process = _FakeProcess();
      var spawnedYet = false;
      final runtime = LocalServeRuntime(
        healthEndpoint: Uri.parse('http://127.0.0.1:8000/health'),
        executable: 'some-serve',
        spawnOnMiss: true,
        pollInterval: const Duration(milliseconds: 5),
        healthTimeout: const Duration(seconds: 2),
        httpClient: MockClient(
          (_) async => spawnedYet
              ? http.Response('ok', 200)
              : throw StateError('refused'),
        ),
        processStarter: (_, _, _) async {
          spawnedYet = true;
          return process;
        },
      );

      expect(await runtime.ensureRunning(), isTrue);
      await runtime.stop();

      expect(process.killed, isTrue);
      expect(runtime.status.$1, LocalServeState.stopped);
      await runtime.dispose();
    });

    test('a throwing diagnostic observer never changes readiness', () async {
      final runtime = LocalServeRuntime(
        healthEndpoint: Uri.parse('http://127.0.0.1:8000/health'),
        executable: 'some-serve',
        onDiagnosticEvent: (_) => throw StateError('observer bug'),
        httpClient: MockClient((_) async => http.Response('ok', 200)),
      );

      expect(await runtime.ensureRunning(), isTrue);
      expect(runtime.isReady, isTrue);
      await runtime.dispose();
    });
  });

  group('LocalHealthProbe', () {
    test('answering status below 500 counts as alive', () async {
      final probe = LocalHealthProbe(
        endpoint: Uri.parse('http://127.0.0.1:8000/health'),
        httpClient: MockClient((_) async => http.Response('not found', 404)),
      );
      expect(await probe.ping(), isTrue);
      await probe.dispose();
    });

    test('connection refused is a miss, not a crash', () async {
      final probe = LocalHealthProbe(
        endpoint: Uri.parse('http://127.0.0.1:8000/health'),
        httpClient: MockClient(
          (_) async => throw StateError('connection refused'),
        ),
      );
      expect(await probe.ping(), isFalse);
      await probe.dispose();
    });
  });
}

final class _FakeProcess implements ManagedServeProcess {
  final Completer<void> _exit = Completer<void>();
  bool killed = false;

  void exit() {
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  int get pid => 424242;

  @override
  void kill() {
    killed = true;
    exit();
  }

  @override
  Future<void> get done => _exit.future;
}
