@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Black-box conformance for `tool/owned_session_p1_leader.pl` (doc/owned_session_p1.md).
void main() {
  group('owned session p1 conformance', () {
    late String perl;
    late String leaderScript;
    late String fixturesDir;

    setUpAll(() async {
      if (Platform.isWindows) return;
      for (final path in const ['/usr/bin/perl', '/bin/perl']) {
        if (File(path).existsSync()) {
          perl = path;
          break;
        }
      }
      expect(perl, isNotEmpty, reason: 'system perl required');
      final entry = await Isolate.resolvePackageUri(
        Uri.parse(
          'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart',
        ),
      );
      expect(entry, isNotNull);
      final packageRoot = File.fromUri(entry!).parent.parent;
      leaderScript = '${packageRoot.path}/tool/owned_session_p1_leader.pl';
      expect(File(leaderScript).existsSync(), isTrue);
      fixturesDir = '${packageRoot.path}/test/fixtures/owned_session_p1';
      for (final name in ['graceful_ok.sh', 'graceful_slow.sh', 'graceful_fail.sh']) {
        await Process.run('chmod', ['+x', '$fixturesDir/$name']);
      }
    });

    test(
      'Windows leader is not part of this POSIX conformance lane',
      () {},
      skip: Platform.isWindows ? false : 'POSIX-only contract',
    );

    test(
      'owned bootstrap: ready line, marker auth, started',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_bootstrap';
        final stderr = <int>[];
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--',
          'sleep',
          '3600',
        ]);
        addTearDown(() async {
          leader.kill();
          await leader.exitCode.timeout(const Duration(seconds: 2));
        });
        leader.stderr.listen(stderr.addAll);
        final client = await binding.server.first.timeout(
          const Duration(seconds: 5),
        );
        final lines = _LineReader(client);
        expect(
          await _readReadyLine(stderr, marker),
          matches(RegExp('^$marker:ready:\\d+:p1:perl\$')),
        );
        expect(await lines.next(), marker);
        expect(await lines.next(), 'started');
        client.writeln('kill');
        await client.flush();
        expect(await _expectKilledGroup(lines), 'killed-group');
        await client.close();
        await leader.exitCode.timeout(const Duration(seconds: 5));
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );

    test(
      'exec failure reports marker:error, not exit 127 contract',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_exec_fail';
        final stderr = StringBuffer();
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--',
          '/no/such/executable/for/p1/conformance',
        ]);
        leader.stderr.transform(utf8.decoder).listen(stderr.write);
        final exitCode = await leader.exitCode.timeout(
          const Duration(seconds: 5),
        );
        expect(exitCode, isNot(127));
        expect(
          stderr.toString(),
          contains('$marker:error:exec:'),
        );
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );

    test(
      'term forwards SIGTERM+CONT to the group',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_term';
        final workDir = Directory.systemTemp.createTempSync('p1-term-');
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--',
          'sh',
          '-c',
          r'trap "" TERM; sleep 3600 & echo $! > member.pid; wait',
        ], workingDirectory: workDir.path);
        addTearDown(() async {
          leader.kill();
          await leader.exitCode.timeout(const Duration(seconds: 2));
          if (workDir.existsSync()) {
            workDir.deleteSync(recursive: true);
          }
        });
        final client = await binding.server.first.timeout(
          const Duration(seconds: 5),
        );
        final lines = _LineReader(client);
        expect(await lines.next(), marker);
        expect(await lines.next(), 'started');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final memberPid = int.parse(
          File('${workDir.path}/member.pid').readAsStringSync().trim(),
        );
        client.writeln('term');
        await client.flush();
        expect(await lines.next(), 'term-forwarded');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          (await Process.run('kill', ['-0', '$memberPid'])).exitCode,
          0,
          reason: 'TERM-ignoring member stays up until KILL',
        );
        client.writeln('kill');
        await client.flush();
        expect(await _expectKilledGroup(lines), 'killed-group');
        await client.close();
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );

    test(
      'graceful hook ok runs before term-forwarded',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_grace_ok';
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--graceful',
          '$fixturesDir/graceful_ok.sh',
          '--graceful-timeout',
          '2',
          '--',
          'sleep',
          '3600',
        ]);
        addTearDown(() async {
          leader.kill();
          await leader.exitCode.timeout(const Duration(seconds: 2));
        });
        final client = await binding.server.first.timeout(
          const Duration(seconds: 5),
        );
        final lines = _LineReader(client);
        expect(await lines.next(), marker);
        expect(await lines.next(), 'started');
        client.writeln('term');
        await client.flush();
        expect(await lines.next(), 'graceful:ok');
        expect(await lines.next(), 'term-forwarded');
        client.writeln('kill');
        await client.flush();
        expect(await _expectKilledGroup(lines), 'killed-group');
        await client.close();
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );

    test(
      'graceful hook timeout still escalates with term-forwarded',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_grace_slow';
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--graceful',
          '$fixturesDir/graceful_slow.sh',
          '--graceful-timeout',
          '1',
          '--',
          'sleep',
          '3600',
        ]);
        addTearDown(() async {
          leader.kill();
          await leader.exitCode.timeout(const Duration(seconds: 2));
        });
        final client = await binding.server.first.timeout(
          const Duration(seconds: 5),
        );
        final lines = _LineReader(client);
        expect(await lines.next(), marker);
        expect(await lines.next(), 'started');
        client.writeln('term');
        await client.flush();
        expect(await lines.next(), 'graceful:timeout');
        expect(await lines.next(), 'term-forwarded');
        client.writeln('kill');
        await client.flush();
        expect(await _expectKilledGroup(lines), 'killed-group');
        await client.close();
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );

    test(
      'graceful hook failure reports graceful:fail then term-forwarded',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_grace_fail';
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--graceful',
          '$fixturesDir/graceful_fail.sh',
          '--',
          'sleep',
          '3600',
        ]);
        addTearDown(() async {
          leader.kill();
          await leader.exitCode.timeout(const Duration(seconds: 2));
        });
        final client = await binding.server.first.timeout(
          const Duration(seconds: 5),
        );
        final lines = _LineReader(client);
        expect(await lines.next(), marker);
        expect(await lines.next(), 'started');
        client.writeln('term');
        await client.flush();
        final graceful = await lines.next();
        expect(graceful, startsWith('graceful:fail:'));
        expect(await lines.next(), 'term-forwarded');
        client.writeln('kill');
        await client.flush();
        expect(await _expectKilledGroup(lines), 'killed-group');
        await client.close();
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );

    test(
      'control EOF kills the admitted target (host-death guard)',
      () async {
        final binding = await _bindControl();
        addTearDown(() => binding.dispose());
        const marker = 'conf_marker_eof';
        final workDir = Directory.systemTemp.createTempSync('p1-eof-');
        final leader = await Process.start(perl, [
          leaderScript,
          '--protocol',
          '1',
          '--mode',
          'owned',
          '--marker',
          marker,
          '--control',
          binding.socketPath,
          '--',
          'sh',
          '-c',
          r'sleep 3600 & echo $! > child.pid; wait',
        ], workingDirectory: workDir.path);
        final client = await binding.server.first.timeout(
          const Duration(seconds: 5),
        );
        final lines = _LineReader(client);
        expect(await lines.next(), marker);
        expect(await lines.next(), 'started');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final childPid = int.parse(
          File('${workDir.path}/child.pid').readAsStringSync().trim(),
        );
        await client.close();
        await leader.exitCode.timeout(const Duration(seconds: 5));
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        var dead = false;
        while (DateTime.now().isBefore(deadline)) {
          if ((await Process.run('kill', ['-0', '$childPid'])).exitCode != 0) {
            dead = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(dead, isTrue, reason: 'leader must kill group on host EOF');
        addTearDown(() async {
          try {
            await Process.run('kill', ['-9', '$childPid']);
          } on Object {
            // Already dead.
          }
          if (workDir.existsSync()) {
            workDir.deleteSync(recursive: true);
          }
        });
      },
      skip: Platform.isWindows ? 'POSIX p1 leader' : null,
    );
  });
}

Future<String> _expectKilledGroup(_LineReader lines) async {
  final line = await lines.next();
  if (line.startsWith('exit:')) {
    return await lines.next();
  }
  return line;
}

Future<String> _readReadyLine(List<int> stderrBytes, String marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final text = utf8.decode(stderrBytes, allowMalformed: true);
    final line = text.split('\n').firstWhere(
      (row) => row.startsWith('$marker:ready:'),
      orElse: () => '',
    );
    if (line.isNotEmpty) return line;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for $marker:ready line');
}

final class _ControlBinding {
  _ControlBinding({
    required this.directory,
    required this.socketPath,
    required this.server,
  });

  final Directory directory;
  final String socketPath;
  final ServerSocket server;

  static Future<_ControlBinding> bind() async {
    final directory = await Directory.systemTemp.createTemp('p1-conf-');
    await Process.run('chmod', ['700', directory.path]);
    final socketPath = '${directory.path}/control.sock';
    final server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    return _ControlBinding(
      directory: directory,
      socketPath: socketPath,
      server: server,
    );
  }

  Future<void> dispose() async {
    try {
      await server.close();
    } on Object {
      // Best-effort.
    }
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Best-effort.
    }
  }
}

Future<_ControlBinding> _bindControl() => _ControlBinding.bind();

final class _LineReader {
  _LineReader(this._socket) {
    _subscription = _socket.listen((chunk) => _buffer.addAll(chunk));
  }

  final Socket _socket;
  final _buffer = <int>[];
  late final StreamSubscription<List<int>> _subscription;

  Future<String> next() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final index = _buffer.indexOf(10);
      if (index >= 0) {
        final line = utf8.decode(
          _buffer.sublist(0, index),
          allowMalformed: true,
        );
        _buffer.removeRange(0, index + 1);
        return line;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('timed out waiting for control line');
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
  }
}
