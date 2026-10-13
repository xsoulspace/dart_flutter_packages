import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bounded_process.dart';

/// Qualified no-fork candidate result with explicit physical cleanup proof.
final class CandidateVerificationResult {
  const CandidateVerificationResult({
    this.process,
    this.refusal,
    this.retainedScratchRoot,
    this.physicallySettled = false,
  });
  final bool physicallySettled;
  final BoundedRunResult? process;
  final String? refusal;

  /// Host cleanup obligation when physical settlement could not be proven.
  final String? retainedScratchRoot;
  bool get ok => physicallySettled && refusal == null && (process?.ok ?? false);
}

/// Host-built verification adapter for private, exclusively owned candidates.
///
/// No model-supplied profiles and no uncontained fallback. On macOS the existing
/// deprecated sandbox-exec mechanism is qualified before each launch. Hosts must
/// separately qualify a supported release helper; this is not App Sandbox or
/// arbitrary-command containment. Fork-capable tools are unsupported here. Candidate files must not be concurrently replaced
/// by another host: existing hard links are refused, new hard links are denied.
/// Deny-default Mach/AppleEvents/network policy and a fork-denied session-leader
/// target provide this lane's boundary. It is not a generic command supervisor.
final class MacOsCandidateVerifier {
  const MacOsCandidateVerifier();

  static const capability = 'macos_no_fork_candidate_v1';

  Future<CandidateVerificationResult> verifyCandidate({
    required String executable,
    required List<String> arguments,
    required String candidateRoot,
    required List<String> readOnlyRoots,
    required Duration deadline,
    bool requiresProcessFork = false,
    List<int> stdinBytes = const [],
    int maxInputBytes = 1 << 20,
    Duration grace = const Duration(seconds: 5),
    int maxCapturedBytes = 1 << 20,
    FutureOr<void> Function(int pid)? onStarted,
  }) async {
    if (requiresProcessFork) {
      return const CandidateVerificationResult(
        refusal: 'candidate_process_fork_unavailable',
        physicallySettled: true,
      );
    }
    if (!Platform.isMacOS || !File('/usr/bin/sandbox-exec').existsSync()) {
      return const CandidateVerificationResult(
        refusal: 'candidate_containment_unavailable: macOS sandbox-exec',
        physicallySettled: true,
      );
    }
    Directory? scratch;
    var mayCleanScratch = true;
    try {
      final candidate = Directory(candidateRoot).resolveSymbolicLinksSync();
      _requireNarrow(candidate);
      final roots = <String>[
        for (final root in readOnlyRoots) _canonicalExisting(root),
      ];
      for (final root in roots) {
        _requireNarrow(root);
      }
      final program = File(executable).resolveSymbolicLinksSync();
      if (!_under(program, candidate) &&
          !roots.any((root) => _under(program, root)) &&
          !_systemReads.any((root) => _under(program, root))) {
        return const CandidateVerificationResult(
          refusal: 'candidate_executable_outside_read_grants',
          physicallySettled: true,
        );
      }
      // Seatbelt cannot make a pre-existing writable hard-link alias safe.
      // The host owns this private candidate throughout audit and execution.
      final links = await runBounded('/usr/bin/find', [
        candidate,
        '-type',
        'f',
        '-links',
        '+1',
        '-print',
        '-quit',
      ], deadline: const Duration(seconds: 10));
      if (!links.ok || links.stdout.isNotEmpty) {
        return CandidateVerificationResult(
          refusal: 'candidate_hard_link_or_audit_unavailable',
          physicallySettled:
              links.survivors.isEmpty && links.settlementProblem == null,
        );
      }
      scratch = Directory.systemTemp.createTempSync('candidate-verification-');
      final temp = scratch.resolveSymbolicLinksSync();
      final home = Directory('$temp/home')..createSync();
      mayCleanScratch = false;
      final (qualification, settled) = await _qualify(temp);
      mayCleanScratch = settled;
      if (qualification != null) {
        return CandidateVerificationResult(
          refusal: qualification,
          physicallySettled: settled,
          retainedScratchRoot: settled ? null : temp,
        );
      }
      final environment = <String, String>{
        'PATH': '${File(program).parent.path}:/usr/bin:/bin',
        'HOME': home.path,
        'TMPDIR': '$temp/',
        'LANG': 'C',
        'LC_ALL': 'C',
        'DART_SUPPRESS_ANALYTICS': 'true',
      };
      mayCleanScratch = false;
      final process = await runBounded(
        '/usr/bin/sandbox-exec',
        [
          '-p',
          _profile([candidate, temp, ...roots], [candidate, temp]),
          program,
          ...arguments,
        ],
        deadline: deadline,
        grace: grace,
        workingDirectory: candidate,
        environment: environment,
        includeParentEnvironment: false,
        singleProcessSession: true,
        stdinBytes: stdinBytes,
        maxInputBytes: maxInputBytes,
        maxCapturedBytes: maxCapturedBytes,
        onStarted: onStarted,
      );
      mayCleanScratch =
          process.survivors.isEmpty && process.settlementProblem == null;
      return CandidateVerificationResult(
        process: process,
        physicallySettled: mayCleanScratch,
        retainedScratchRoot: mayCleanScratch ? null : temp,
      );
    } on Object catch (error) {
      return CandidateVerificationResult(
        refusal: 'candidate_containment_preparation_failed: $error',
        physicallySettled: mayCleanScratch,
        retainedScratchRoot: mayCleanScratch ? null : scratch?.path,
      );
    } finally {
      // Never remove storage potentially used by a reported live survivor.
      // runBounded's named settlement limitations remain in the returned result.
      if (mayCleanScratch && scratch != null && scratch.existsSync()) {
        scratch.deleteSync(recursive: true);
      }
    }
  }
}

const _systemReads = [
  '/System/Library',
  '/usr/lib',
  '/usr/bin',
  '/bin',
  '/usr/share',
];

String _canonicalExisting(String path) {
  final type = FileSystemEntity.typeSync(path);
  return type == FileSystemEntityType.directory
      ? Directory(path).resolveSymbolicLinksSync()
      : File(path).resolveSymbolicLinksSync();
}

void _requireNarrow(String root) {
  if (const [
        '/',
        '/Users',
        '/private',
        '/private/var',
        '/Volumes',
        '/tmp',
        '/private/tmp',
      ].contains(root) ||
      root == Platform.environment['HOME']) {
    throw ArgumentError('Broad root is not an admitted candidate/read grant');
  }
}

bool _under(String path, String root) =>
    path == root || path.startsWith('$root/');

String _profile(List<String> reads, List<String> writes) {
  String filters(Iterable<String> roots) =>
      roots.map((root) => '(subpath ${jsonEncode(root)})').join(' ');
  return '''(version 1)
(deny default)
(allow process-exec)
(deny process-fork)
(allow file-read-metadata)
(allow sysctl-read)
(allow file-ioctl (literal "/dev/null") (literal "/dev/random") (literal "/dev/urandom"))
(allow file-read-data (literal "/")
  ${filters([..._systemReads, ...reads])}
  (literal "/dev/null") (literal "/dev/random") (literal "/dev/urandom"))
(allow file-write* ${filters(writes)} (literal "/dev/null"))
(deny file-link)
''';
}

Future<(String?, bool)> _qualify(String temp) async {
  final allowed = Directory('$temp/probe')..createSync();
  final denied = File('$temp/secret')..writeAsStringSync('synthetic-secret');
  final marker = File('$temp/untouched')..writeAsStringSync('original');
  final profile = _profile([allowed.path], [allowed.path]);
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  var connected = false;
  final listener = server.listen((socket) {
    connected = true;
    socket.write('HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok');
    socket.close();
  });
  try {
    final probe = await runBounded(
      '/usr/bin/sandbox-exec',
      [
        '-p',
        profile,
        '/usr/bin/perl',
        '-MPOSIX',
        '-MSocket',
        '-e',
        r'''my ($inside,$secret,$marker,$port)=@ARGV;
open(my $ok, ">", "$inside/inside") or exit 40; print $ok "allowed"; close($ok);
if (open(my $bad, "<", $secret)) { exit 41; }
if (open(my $bad, ">", $marker)) { exit 42; }
if (link("$inside/inside", "$inside/link")) { exit 43; }
if (socket(my $sock, AF_INET, SOCK_STREAM, 0)) {
  if (connect($sock, sockaddr_in($port, inet_aton("127.0.0.1")))) { exit 44; }
}
my $pid = fork();
if (defined($pid)) { if ($pid == 0) { exit 45; } waitpid($pid,0); exit 45; }
if (POSIX::setsid() >= 0) { exit 46; }
print "qualified";
''',
        allowed.path,
        denied.path,
        marker.path,
        '${server.port}',
      ],
      deadline: const Duration(seconds: 10),
      environment: const {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C'},
      includeParentEnvironment: false,
      singleProcessSession: true,
    );
    if (!probe.ok ||
        connected ||
        probe.stdout != 'qualified' ||
        marker.readAsStringSync() != 'original' ||
        !File('${allowed.path}/inside').existsSync() ||
        File('${allowed.path}/link').existsSync()) {
      return (
        'candidate_containment_self_test_failed',
        probe.survivors.isEmpty && probe.settlementProblem == null,
      );
    }
    return (null, true);
  } finally {
    await listener.cancel();
    await server.close();
  }
}
