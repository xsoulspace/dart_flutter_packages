@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  late Directory base;
  late Directory candidate;
  const verifier = MacOsCandidateVerifier();

  setUp(() {
    base = Directory.systemTemp.createTempSync('contained-test-');
    candidate = Directory('${base.path}/candidate')..createSync();
  });
  tearDown(() => base.deleteSync(recursive: true));

  test(
    'no-fork execution denies canonical/volume-alias reads and network',
    () async {
      final secret = File('${base.path}/secret')
        ..writeAsStringSync('synthetic');
      final outside = File('${base.path}/outside')
        ..writeAsStringSync('untouched');
      final canonical = secret.resolveSymbolicLinksSync();
      final volumeAlias = '/System/Volumes/Data$canonical';
      Link('${candidate.path}/alias').createSync(secret.path);
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var reached = false;
      final subscription = server.listen((socket) {
        reached = true;
        socket.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close();
      });
      final result = await verifier.verifyCandidate(
        executable: '/usr/bin/perl',
        arguments: [
          '-MPOSIX',
          '-MSocket',
          '-e',
          r'''
my ($secret,$outside,$port,$volumeAlias)=@ARGV;
open(my $local, ">", "local") or exit 10; print $local "inside"; close($local);
for my $path ($secret,$volumeAlias,"alias") {
  if (open(my $bad,"<",$path)) { exit 11; }
}
for my $path ($outside,"alias") {
  if (open(my $bad,">",$path)) { exit 12; }
}
if (link("local","linked")) { exit 13; }
if (socket(my $sock,AF_INET,SOCK_STREAM,0)) {
  if (connect($sock,sockaddr_in($port,inet_aton("127.0.0.1")))) { exit 14; }
}
my $child=fork();
if (defined($child)) { if ($child==0) { exit 15; } waitpid($child,0); exit 15; }
if (POSIX::setsid()>=0) { exit 16; }
print "passed";
''',
          secret.path,
          outside.path,
          '${server.port}',
          volumeAlias,
        ],
        candidateRoot: candidate.path,
        readOnlyRoots: [],
        deadline: const Duration(seconds: 10),
      );
      expect(
        result.ok,
        isTrue,
        reason: '${result.refusal} ${result.process?.stderr}',
      );
      expect(result.physicallySettled, isTrue);
      expect(result.process!.stdout, 'passed');
      expect(secret.readAsStringSync(), 'synthetic');
      expect(outside.readAsStringSync(), 'untouched');
      expect(File('${candidate.path}/local').readAsStringSync(), 'inside');
      expect(File('${candidate.path}/linked').existsSync(), isFalse);
      expect(reached, isFalse);
    },
  );

  test('fork-capable command refuses without executing or fallback', () async {
    final result = await verifier.verifyCandidate(
      executable: '/bin/sh',
      arguments: ['-c', 'printf bad > marker'],
      candidateRoot: candidate.path,
      readOnlyRoots: [],
      requiresProcessFork: true,
      deadline: const Duration(seconds: 5),
    );
    expect(result.refusal, 'candidate_process_fork_unavailable');
    expect(result.process, isNull);
    expect(result.physicallySettled, isTrue);
    expect(File('${candidate.path}/marker').existsSync(), isFalse);
  });

  test('pre-existing hardlink refuses before executing candidate', () async {
    final outside = File('${base.path}/outside')..writeAsStringSync('original');
    final link = await Process.run('/bin/ln', [
      outside.path,
      '${candidate.path}/alias',
    ]);
    expect(link.exitCode, 0);
    final result = await verifier.verifyCandidate(
      executable: '/bin/sh',
      arguments: ['-c', 'printf bad > alias'],
      candidateRoot: candidate.path,
      readOnlyRoots: [],
      deadline: const Duration(seconds: 5),
    );
    expect(result.refusal, 'candidate_hard_link_or_audit_unavailable');
    expect(result.process, isNull);
    expect(outside.readAsStringSync(), 'original');
  });

  test(
    'real SDK compiles and executes candidate with explicit read roots',
    () async {
      final dart = File(Platform.resolvedExecutable).resolveSymbolicLinksSync();
      const flutterEngineMarker = '/bin/cache/artifacts/engine/';
      final marker = dart.indexOf(flutterEngineMarker);
      final sdk = marker < 0
          ? File(dart).parent.parent.path
          : '${dart.substring(0, marker)}/bin/cache/dart-sdk';
      final dartVm = '$sdk/bin/dart';
      File('${candidate.path}/main.dart').writeAsStringSync('''
import 'dart:io';
import 'dart:convert';
Future<void> main() async {
  try {
    final child = await Process.start('/bin/sleep', ['30']);
    child.kill(); await child.exitCode;
    throw StateError('candidate subprocess creation was unexpectedly allowed');
  } on ProcessException {
    // Native Process.start/posix_spawn must be refused, not only Perl fork.
  }
  final input=stdin.readLineSync()!;
  File('result').writeAsStringSync('compiled');
  print(input.split(' ').map(int.parse).fold<int>(0,(a,b)=>a+b));
}
''');
      final compile = await verifier.verifyCandidate(
        executable: '$sdk/bin/dartaotruntime',
        arguments: [
          '$sdk/bin/snapshots/gen_kernel_aot.dart.snapshot',
          '--platform',
          '$sdk/lib/_internal/vm_platform_strong.dill',
          'main.dart',
          '-o',
          'main.dill',
        ],
        candidateRoot: candidate.path,
        readOnlyRoots: [sdk],
        deadline: const Duration(seconds: 30),
      );
      expect(compile.refusal, isNull, reason: '${compile.refusal}');
      expect(compile.ok, isTrue, reason: '${compile.process?.stderr}');
      expect(File('${candidate.path}/main.dill').existsSync(), isTrue);
      final execute = await verifier.verifyCandidate(
        executable: dartVm,
        arguments: ['--disable-dart-dev', 'main.dill'],
        stdinBytes: utf8.encode('12 30\n'),
        maxInputBytes: 64,
        candidateRoot: candidate.path,
        readOnlyRoots: [sdk],
        deadline: const Duration(seconds: 10),
      );
      expect(
        execute.ok,
        isTrue,
        reason: '${execute.refusal} ${execute.process?.stderr}',
      );
      expect(execute.process!.stdout.trim(), '42');
      expect(execute.process!.inputProblem, isNull);
      expect(execute.physicallySettled, isTrue);
      expect(File('${candidate.path}/result').readAsStringSync(), 'compiled');
    },
  );

  test('no-fork session-leader target settles at deadline', () async {
    final unrelated = await Process.start('/bin/sleep', ['30']);
    addTearDown(() async {
      unrelated.kill();
      await unrelated.exitCode;
    });
    final result = await verifier.verifyCandidate(
      executable: '/usr/bin/perl',
      arguments: ['-e', 'select STDOUT; \$|=1; print "waiting\\n"; sleep 30;'],
      candidateRoot: candidate.path,
      readOnlyRoots: [],
      deadline: const Duration(milliseconds: 300),
      grace: const Duration(milliseconds: 300),
    );
    expect(result.refusal, isNull);
    final process = result.process!;
    expect(process.cause, BoundedProcessCause.killedOnDeadline);
    expect(process.survivors, isEmpty);
    expect(process.settlementProblem, isNull);
    expect(result.physicallySettled, isTrue);
    expect(
      (await Process.run('/bin/kill', ['-0', '${process.pid}'])).exitCode,
      isNot(0),
    );
    expect(
      (await Process.run('/bin/kill', ['-0', '${unrelated.pid}'])).exitCode,
      0,
    );
    expect(result.retainedScratchRoot, isNull);
  });

  test(
    'Mach/AppleEvents service lookup refused without sending events',
    () async {
      final source = File('${candidate.path}/lookup.c')
        ..writeAsStringSync(r'''
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <stdio.h>
int main() {
 mach_port_t port;
 kern_return_t result=bootstrap_look_up(bootstrap_port,
   "com.apple.coreservices.appleevents",&port);
 printf("%d\n",result);
 return 0;
}
''');
      final helper = '${candidate.path}/lookup';
      final compile = await runBounded('/usr/bin/clang', [
        source.path,
        '-o',
        helper,
      ], deadline: const Duration(seconds: 30));
      expect(compile.ok, isTrue, reason: compile.stderr);
      final control = await Process.run(helper, []);
      expect(control.exitCode, 0);
      expect(
        control.stdout.toString().trim(),
        '0',
        reason: 'live service required as independent oracle',
      );
      final result = await verifier.verifyCandidate(
        executable: helper,
        arguments: [],
        candidateRoot: candidate.path,
        readOnlyRoots: [],
        deadline: const Duration(seconds: 10),
      );
      expect(
        result.ok,
        isTrue,
        reason: '${result.refusal} ${result.process?.stderr}',
      );
      expect(result.process!.stdout.trim(), '1100');
      expect(result.physicallySettled, isTrue);
    },
  );
}
