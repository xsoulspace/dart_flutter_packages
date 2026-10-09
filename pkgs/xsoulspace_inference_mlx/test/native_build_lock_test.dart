import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../hook/native_build_lock.dart';

void main() {
  test('failed builder releases the persistent lock', () async {
    final root = await Directory.systemTemp.createTemp('mlx_lock_failure_');
    try {
      final lock = File('${root.path}/hook.lock');
      await expectLater(
        withNativeBuildLock<void>(lock, () async => throw StateError('build')),
        throwsStateError,
      );
      expect(lock.existsSync(), isTrue);
      expect(await withNativeBuildLock(lock, () async => 'next'), 'next');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('three hook processes serialize across handoff on one lock', () async {
    final root = await Directory.systemTemp.createTemp('mlx_lock_processes_');
    final processes = <Process>[];
    final exits = <String, Future<int>>{};
    final finished = <Process>{};
    final errors = <String, StringBuffer>{};
    final helper = File('hook/native_build_lock.dart').absolute.uri;
    final fixture = File('${root.path}/builder.dart');
    await fixture.writeAsString('''
import 'dart:async';
import 'dart:io';
import '$helper';
Future<void> main(List<String> args) async {
 final root=args[0], id=args[1];
 File('\$root/\$id.waiting').writeAsStringSync('waiting', flush:true);
 await withNativeBuildLock(File('\$root/hook.lock'), () async {
  File('\$root/\$id.entered').writeAsStringSync('entered', flush:true);
  while(!File('\$root/\$id.release').existsSync()) {
   await Future<void>.delayed(const Duration(milliseconds:10));
  }
 });
}
''');
    Future<void> start(String id) async {
      final p = await Process.start(Platform.resolvedExecutable, [
        fixture.path,
        root.path,
        id,
      ]);
      processes.add(p);
      errors[id] = StringBuffer();
      p.stderr.transform(SystemEncoding().decoder).listen(errors[id]!.write);
      p.stdout.drain<void>();
      exits[id] = p.exitCode.then((code) {
        finished.add(p);
        return code;
      });
    }

    Future<void> until(String marker) async {
      final watch = Stopwatch()..start();
      while (!File('${root.path}/$marker').existsSync()) {
        if (watch.elapsed > const Duration(seconds: 5)) {
          fail('missing $marker: $errors');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    void release(String id) => File(
      '${root.path}/$id.release',
    ).writeAsStringSync('release', flush: true);

    try {
      await start('A');
      await until('A.entered');
      await start('B');
      await until('B.waiting');
      expect(File('${root.path}/B.entered').existsSync(), isFalse);
      release('A');
      expect(await exits['A'], 0, reason: '${errors['A']}');
      await until('B.entered');
      expect(File('${root.path}/hook.lock').existsSync(), isTrue);
      await start('C');
      await until('C.waiting');
      // Let C's lock attempt execute while B retains the physical build lease.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(File('${root.path}/C.entered').existsSync(), isFalse);
      release('B');
      expect(await exits['B'], 0, reason: '${errors['B']}');
      await until('C.entered');
      release('C');
      expect(await exits['C'], 0, reason: '${errors['C']}');
      expect(File('${root.path}/hook.lock').existsSync(), isTrue);
    } finally {
      for (final p in processes) {
        p.kill();
        await p.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            p.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      }
      await root.delete(recursive: true);
    }
  });
}
