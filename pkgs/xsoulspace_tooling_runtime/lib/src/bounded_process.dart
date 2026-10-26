// ignore_for_file: lines_longer_than_80_chars

/// Bounded process runs: spawn, capture, deadline, tree-aware
/// TERM→KILL escalation, verified death.
///
/// Modeled on oka's resource-composition seam (oka ADR-0026) but
/// SELF-CONTAINED: no package imports. The law it enforces: a run that
/// hits its deadline STOPS the process tree it spawned and awaits the
/// exit — never a synthetic timeout result over a live child (the
/// orphan vector: `Process.run(...).timeout(...)` returns while
/// `dart test` / `flutter test` keeps running).
///
/// Mechanics:
/// 1. the process tree is enumerated (`ps -eo pid=,ppid=,stat=`) BEFORE
///    the first signal — identity-before-signal;
/// 2. SIGTERM → grace → SIGKILL escalation;
/// 3. exitCode is ALWAYS awaited; survivors (should be none) are
///    reported as named data, never swallowed.
///
/// Windows: `ps` is unavailable; the tree then degrades to the root pid
/// alone. A full `taskkill /PID <pid> /T /F` (tree kill, no grace
/// ladder) is the recorded follow-up — a named limitation, not a silent
/// downgrade.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

import 'owned_session_launch_embed.dart';

part 'bounded_duplex.dart';
part 'bounded_session_protocol.dart';

/// Why a bounded run ended — the terminal causes a bounded RUN can
/// produce (exited / signaled / killedOnDeadline / spawnFailed).
enum BoundedProcessCause {
  /// Exited by itself before the deadline.
  exited,

  /// Died by a signal it did not handle (negative exit code) before the
  /// deadline.
  signaled,

  /// The deadline fired and termination targeted the observed tree.
  /// [BoundedRunResult.survivors] retains live or unobservable PIDs.
  killedOnDeadline,

  /// The process never spawned (executable missing / not runnable).
  spawnFailed,

  /// Explicit native owner disposal or bounded duplex refusal.
  stoppedByOwner,
}

/// The outcome of one bounded run.
final class BoundedRunResult {
  const BoundedRunResult({
    required this.cause,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.signaledPids,
    required this.survivors,
    this.pid,
    this.spawnError,
    this.settlementProblem,
    this.inputProblem,
    this.transportProblem,
  });

  /// Terminal cause — the meaning of the run's end.
  final BoundedProcessCause cause;

  /// Exit code; -1 when no exit was observed (spawn failure).
  final int exitCode;

  /// Captured stdout (bounded, tail kept).
  final String stdout;

  /// Captured stderr (bounded, tail kept).
  final String stderr;

  /// The spawned root pid, when it spawned.
  final int? pid;

  /// Known targets observed before group/tree signals. A POSIX group signal
  /// can also reach a child forked between observation and delivery; this is
  /// not an exhaustive history of every PID reached by the kernel.
  final List<int> signaledPids;

  /// Signaled pids still alive after the ladder — the named orphan
  /// defect. An empty list is the invariant.
  final List<int> survivors;

  /// Spawn failure message when [cause] is
  /// [BoundedProcessCause.spawnFailed].
  final String? spawnError;

  /// Named observation/escaped-pipe limitation; never certified settlement.
  final String? settlementProblem;

  /// Host input write/flush/close failure; output alone cannot certify success.
  final String? inputProblem;

  /// Bounded duplex protocol/IO refusal, separate from physical settlement.
  final String? transportProblem;

  bool get physicallySettled =>
      pid != null && survivors.isEmpty && settlementProblem == null;

  bool get ok =>
      cause == BoundedProcessCause.exited &&
      exitCode == 0 &&
      survivors.isEmpty &&
      settlementProblem == null &&
      inputProblem == null && transportProblem == null;
}

/// Runs [executable] with [arguments] under [deadline]: on timeout the
/// observed process tree is stopped (TERM → [grace] → KILL, enumerated before
/// the first signal), the exit is awaited, and the result names what
/// happened. Output is captured with a per-stream byte bound
/// ([maxCapturedBytes], tail kept).
/// [onStarted] observes the admitted PID after capture and the deadline are
/// installed. Observer errors are guarded and its future is not awaited.
/// POSIX targets launch in an acknowledged private session via the trusted
/// system Perl helper; missing helper/observation refuses by name. The deadline
/// owns root exit, pipe drain and live group members together. Other groups and
/// descendants creating a new session are never guessed or signaled. An escaped
/// inherited pipe is named unsettled; this primitive is not an OS sandbox.
/// Callers retain ownership of reported survivors until observed.
/// [singleProcessSession] is for a host-enforced fork-denied target. It execs
/// the target in the admitted session-leader PID; readiness then precedes exec.
/// Supplied [stdinBytes] are bounded by [maxInputBytes], copied before launch,
/// flushed and closed under the same deadline. Null retains legacy stdin
/// behavior; an empty list delivers EOF. Input failures are named in the result.
/// It does not enforce the no-fork policy itself and must not be used as a
/// generic descendant-containment claim.
Future<BoundedRunResult> runBounded(
  String executable,
  List<String> arguments, {
  required Duration deadline,
  Duration grace = const Duration(seconds: 5),
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool singleProcessSession = false,
  List<int>? stdinBytes,
  int maxInputBytes = 1 << 20,
  int maxCapturedBytes = 1 << 20,
  FutureOr<void> Function(int pid)? onStarted,
  void Function(BoundedDuplexHandle handle)? onDuplexReady,
  BoundedDuplexLimits duplexLimits = const BoundedDuplexLimits(),
}) async {
  if ((onDuplexReady != null && (stdinBytes != null || !duplexLimits.valid)) ||
      maxInputBytes < 0 ||
      (stdinBytes != null &&
          (stdinBytes.length > maxInputBytes ||
              stdinBytes.any((byte) => byte < 0 || byte > 255)))) {
    return const BoundedRunResult(
      cause: BoundedProcessCause.spawnFailed,
      exitCode: -1,
      stdout: '',
      stderr: '',
      signaledPids: [],
      survivors: [],
      spawnError:
          'admitted stdin exceeds input budget or contains invalid bytes',
    );
  }
  final input = stdinBytes == null ? null : List<int>.unmodifiable(stdinBytes);
  final marker =
      'bounded_${Random.secure().nextInt(1 << 32)}_'
      '${Random.secure().nextInt(1 << 32)}';
  String? launcher;
  if (!Platform.isWindows) {
    for (final path in const ['/usr/bin/perl', '/bin/perl']) {
      if (File(path).existsSync()) {
        launcher = path;
        break;
      }
    }
    if (launcher == null || await _groupRows() == null) {
      return const BoundedRunResult(
        cause: BoundedProcessCause.spawnFailed,
        exitCode: -1,
        stdout: '',
        stderr: '',
        signaledPids: [],
        survivors: [],
        spawnError: 'owned POSIX process session unavailable (perl/ps)',
      );
    }
  }
  final spawnEnvironment = <String, String>{
    if (includeParentEnvironment) ...Platform.environment,
    ...?environment,
  };
  _SessionControlBinding? controlBinding;
  if (launcher != null && !singleProcessSession) {
    controlBinding = await _SessionControlBinding.bind();
    if (controlBinding == null) {
      return const BoundedRunResult(
        cause: BoundedProcessCause.spawnFailed,
        exitCode: -1,
        stdout: '',
        stderr: '',
        signaledPids: [],
        survivors: [],
        spawnError: 'owned POSIX session control socket unavailable',
      );
    }
  }
  Process process;
  try {
    process = await Process.start(
      launcher ?? executable,
      launcher == null
          ? arguments
          : singleProcessSession
          ? [
              '-MPOSIX',
              '-e',
              _singleProcessSessionLaunch,
              '--',
              marker,
              executable,
              ...arguments,
            ]
          : [
              '-MPOSIX',
              '-e',
              ownedSessionLaunchEmbed,
              '--',
              '--protocol',
              _sessionProtocolVersion,
              '--mode',
              'owned',
              '--marker',
              marker,
              '--control',
              controlBinding!.socketPath,
              '--',
              executable,
              ...arguments,
            ],
      workingDirectory: workingDirectory,
      environment: spawnEnvironment,
      includeParentEnvironment: false,
    );
  } on ProcessException catch (e) {
    return BoundedRunResult(
      cause: BoundedProcessCause.spawnFailed,
      exitCode: -1,
      stdout: '',
      stderr: '',
      signaledPids: const [],
      survivors: const [],
      spawnError: e.message,
    );
  }
  final duplex = onDuplexReady == null
      ? null
      : BoundedDuplexHandle._(process.stdin, duplexLimits);
  final out = _BoundedCapture(maxCapturedBytes);
  final err = _BoundedCapture(maxCapturedBytes);
  final owned = launcher == null
      ? null
      : _OwnedProcessGroup(
          process,
          controlBinding: controlBinding,
          marker: marker,
          tightDeadline: deadline < const Duration(seconds: 1),
        );
  if (owned != null) {
    _ownedProcessGroups[process.pid] = owned;
  }
  final startup = Completer<void>();
  final channelStarted = owned != null && !singleProcessSession
      ? Completer<void>()
      : null;
  final header = <int>[];
  var headerPending = owned != null;
  String? startupError;
  var startupFailureReported = false;
  final outDone = Completer<void>();
  final errDone = Completer<void>();
  final outSubscription = process.stdout.listen(
    (chunk) {
      out.add(chunk);
      duplex?._receive(chunk);
    },
    onDone: () {
      duplex?._outputClosed();
      outDone.complete();
    },
    onError: (Object _) {
      if (!outDone.isCompleted) outDone.complete();
    },
  );
  final statusBytes = <int>[];
  final startedBytes = singleProcessSession
      ? utf8.encode('$marker:started\n')
      : null;
  final failureBytes = utf8.encode('$marker:error:');
  void captureStatus(List<int> chunk) {
    if (startup.isCompleted) {
      err.add(chunk);
      return;
    }
    if (channelStarted != null) {
      err.add(chunk);
      return;
    }
    statusBytes.addAll(chunk);
    final started = startedBytes == null
        ? -1
        : _byteSequenceIndex(statusBytes, startedBytes);
    final failed = _byteSequenceIndex(statusBytes, failureBytes);
    if (started >= 0) {
      err.add(statusBytes.sublist(0, started));
      err.add(statusBytes.sublist(started + startedBytes!.length));
      statusBytes.clear();
      startup.complete();
    } else if (failed >= 0) {
      final end = statusBytes.indexOf(10, failed);
      if (end >= 0) {
        startupFailureReported = true;
        startupError = utf8.decode(
          statusBytes.sublist(failed + failureBytes.length, end),
          allowMalformed: true,
        );
        err.add(statusBytes.sublist(0, failed));
        err.add(statusBytes.sublist(end + 1));
        statusBytes.clear();
        startup.complete();
      }
    } else if (statusBytes.length > maxCapturedBytes + 4096) {
      // Target output may precede the private successful-exec notice. Keep
      // capture bounded while retaining enough suffix for a split notice.
      final cut = statusBytes.length - 4096;
      err.add(statusBytes.sublist(0, cut));
      statusBytes.removeRange(0, cut);
    }
  }

  final errSubscription = process.stderr.listen(
    (chunk) {
      if (!headerPending) {
        captureStatus(chunk);
        return;
      }
      header.addAll(chunk);
      final end = header.indexOf(10);
      if (end < 0) return;
      final first = utf8.decode(header.sublist(0, end), allowMalformed: true);
      final readyOwned =
          RegExp('^$marker:ready:(\\d+):p$_sessionProtocolVersion:perl\$');
      final readySingle = singleProcessSession
          ? first.startsWith('$marker:ready:')
          : readyOwned.hasMatch(first);
      if (owned != null && readySingle) {
        owned.ready = true;
      } else {
        startupFailureReported = first.startsWith('$marker:error:');
        startupError = first.startsWith('$marker:error:')
            ? first.substring('$marker:error:'.length)
            : 'owned process session did not acknowledge its launch';
        startup.complete();
      }
      headerPending = false;
      captureStatus(header.sublist(end + 1));
      header.clear();
    },
    onDone: () {
      if (!startup.isCompleted) {
        startupError =
            'owned process session ended before exec acknowledgement';
        err.add(statusBytes);
        statusBytes.clear();
        startup.complete();
      }
      if (!errDone.isCompleted) errDone.complete();
    },
    onError: (Object _) {
      startupError ??= 'owned process session observation failed';
      if (!startup.isCompleted) startup.complete();
      if (!errDone.isCompleted) errDone.complete();
    },
  );
  if (owned != null && !singleProcessSession && controlBinding != null) {
    unawaited(() async {
      final socket = await _acceptSessionControl(controlBinding!);
      if (socket == null) {
        startupError = 'owned session control socket accept failed';
        if (!channelStarted!.isCompleted) channelStarted.complete();
        if (!startup.isCompleted) startup.complete();
        return;
      }
      owned.controlSocket = socket;
      owned.controlSink = socket;
      unawaited(_listenSessionControl(
        owned,
        channelStarted!,
        startup,
        marker: marker,
      ));
    }());
  }
  if (owned == null) startup.complete();

  var fired = false;
  var finished = false;
  int? exitCode;
  final rootDone = process.exitCode.then((code) {
    exitCode = code;
    if (owned != null) owned.rootExited = true;
  });
  final ladder = Completer<List<int>>();
  var ownerStopped = false;
  void stopOwned({required bool deadlineExpired}) {
    if (finished || fired || ownerStopped) return;
    fired = deadlineExpired;
    ownerStopped = !deadlineExpired;
    if (owned?.tightDeadline == true) {
      owned!.deadlineArmed = false;
    }
    unawaited(() async {
      try {
        ladder.complete(
          owned == null
              ? await stopProcessTree(process.pid, grace: grace)
              : await _stopOwnedProcessGroup(owned, grace: grace),
        );
      } on Object catch (error, stack) {
        ladder.completeError(error, stack);
      }
    }());
  }
  duplex?._stop = () => stopOwned(deadlineExpired: false);
  Timer? deadlineTimer;
  final inputDone = Completer<void>();
  String? inputProblem;
  if (duplex != null) {
    unawaited(duplex._inputClosed.future.then((_) {
      inputDone.complete();
    }));
  } else if (input == null) {
    inputDone.complete();
  } else {
    // Observe stdin sink failures for the whole admission; bytes are queued
    // only after the owned leader reports `started` (or spawn ack for direct).
    unawaited(
      process.stdin.done.catchError((Object error) {
        inputProblem ??= 'admitted stdin sink failed: $error';
      }),
    );
  }
  Future<void> startAdmittedInput() async {
    if (input == null || duplex != null || inputDone.isCompleted) return;
    try {
      const chunkSize = 64 * 1024;
      for (var offset = 0; offset < input.length; offset += chunkSize) {
        if (fired || ownerStopped) {
          inputProblem ??= 'admitted stdin did not settle after deadline';
          return;
        }
        final end = offset + chunkSize > input.length
            ? input.length
            : offset + chunkSize;
        process.stdin.add(input.sublist(offset, end));
        await process.stdin.flush();
      }
      try {
        await process.stdin.close();
      } on Object catch (error) {
        inputProblem ??= 'admitted stdin close failed: $error';
      }
      if (inputProblem == null && !inputDone.isCompleted) {
        inputDone.complete();
      }
    } on Object catch (error) {
      inputProblem ??= 'admitted stdin write/flush failed: $error';
      if (!inputDone.isCompleted) inputDone.complete();
    }
  }
  // Session acknowledgement is stripped from stderr; argv, target output and
  // working directory stay unchanged. Observers cannot cancel before capture
  // and the deadline own the complete process/pipe lifetime.
  await startup.future;
  if (channelStarted != null && startupError == null) {
    await channelStarted.future;
    startupError = owned?.controlFailure;
  }
  if (startupError == null) {
    deadlineTimer = Timer(deadline, () => stopOwned(deadlineExpired: true));
  }
  if (startupError == null && input != null && duplex == null) {
    unawaited(startAdmittedInput());
  }
  if (startupError == null && duplex != null) {
    try {
      onDuplexReady!(duplex);
    } on Object {
      duplex._refuse('duplex_ready_callback_failed');
    }
  }
  if (startupError == null && onStarted != null) {
    unawaited(
      Future<void>.sync(() => onStarted(process.pid)).catchError((Object _) {}),
    );
  }
  if (owned != null && !singleProcessSession && startupError == null) {
    unawaited(_watchSessionSettle(owned));
  }

  Future<void> normalLifetime() async {
    if (owned != null && !singleProcessSession) {
      await inputDone.future;
      // The Dart [process] handle is the owned leader; the admitted target may
      // exit first while the leader keeps inherited pipe ends open until settle.
      // Settlement is driven by `exit:` / group observation, not stdout/stderr EOF.
      while (!finished) {
        if (owned.settleAcknowledged.isCompleted) {
          await rootDone;
          return;
        }
        final members = await _ownedGroupMembers(owned);
        if (!owned._deadlineBlocksSettle &&
            !owned.settleRequested &&
            owned.reportedWaitStatus != null &&
            members != null &&
            await _onlyLeaderRemainsLive(members, owned)) {
          await _requestSessionSettle(owned);
        }
        if (owned.settleRequested && !owned.settleAcknowledged.isCompleted) {
          await owned.settleAcknowledged.future;
          await rootDone;
          return;
        }
        if (members != null && members.isEmpty) {
          await rootDone;
          return;
        }
        final leaderAlive = await _pidAlive(owned.process.pid);
        if (leaderAlive == false) {
          await rootDone;
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return;
    }
    await rootDone;
    await duplex?._closeInput();
    await Future.wait([outDone.future, errDone.future, inputDone.future]);
  }

  final natural = normalLifetime();
  // Deadline termination also bounds inherited pipes from an escaped session.
  // Such an escape is named unsettled, never killed by a guessed PID.
  await Future.any<void>([
    natural,
    ladder.future.then((_) async {
      await Future.any<void>([natural, Future<void>.delayed(grace)]);
    }),
  ]);
  finished = true;
  deadlineTimer?.cancel();
  if (owned != null && !singleProcessSession) {
    if (!owned.settleAcknowledged.isCompleted) {
      await _requestSessionSettle(owned);
      await owned.settleAcknowledged.future.timeout(
        grace,
        onTimeout: () {},
      );
    }
    await owned.disposeControl();
  }
  final signaled = fired || ownerStopped
      ? await ladder.future
      : const <int>[];
  final streamsComplete = outDone.isCompleted && errDone.isCompleted;
  if (!streamsComplete) {
    await outSubscription.cancel();
    await errSubscription.cancel();
    if (!outDone.isCompleted) outDone.complete();
    if (!errDone.isCompleted) errDone.complete();
  }
  final survivors = <int>{
    for (final pid in signaled)
      if (await _pidAlive(pid) != false) pid,
  };
  String? settlementProblem;
  if (!inputDone.isCompleted) {
    inputProblem ??= 'admitted stdin did not settle after deadline';
    if (!(fired || ownerStopped)) {
      settlementProblem = 'admitted stdin remained unsettled';
    }
  }
  if (owned != null) {
    if (!fired && owned.settleAcknowledged.isCompleted) {
      await rootDone;
    }
    final remaining = await _ownedGroupMembers(owned);
    if (remaining == null) {
      settlementProblem ??= 'owned session observation unavailable';
      if (fired) {
        survivors.add(process.pid);
      }
    } else {
      for (final pid in remaining) {
        if (await _pidAlive(pid) != false) survivors.add(pid);
      }
    }
    if (!streamsComplete && !(fired || ownerStopped)) {
      if (await _pidAlive(process.pid) != false) {
        survivors.add(process.pid);
      }
      settlementProblem ??=
          'inherited pipe remained open outside settled session';
    }
    if (owned.unsettledReason != null) {
      settlementProblem ??= 'owned session ${owned.unsettledReason}';
    }
    _ownedProcessGroups.remove(process.pid);
  }
  if (exitCode == null) {
    survivors.add(process.pid);
    settlementProblem ??= 'spawned root exit was not observed';
  }
  final text = err.text;
  if (startupError != null &&
      survivors.isEmpty &&
      (!fired || startupFailureReported)) {
    final result = BoundedRunResult(
      cause: BoundedProcessCause.spawnFailed,
      exitCode: -1,
      stdout: out.text,
      stderr: '',
      signaledPids: signaled,
      survivors: const [],
      pid: process.pid,
      spawnError: startupError,
      inputProblem: inputProblem,
      transportProblem: duplex?.problem,
    );
    duplex?._settled.complete(result);
    return result;
  }
  final result = BoundedRunResult(
    cause: ownerStopped
        ? BoundedProcessCause.stoppedByOwner
        : owned?.externallyStopped == true && !fired
        ? BoundedProcessCause.signaled
        : deadlineCause(fired: fired, exitCode: exitCode ?? -1),
    exitCode: owned?.reportedWaitStatus != null
        ? _waitStatusExitCode(owned!.reportedWaitStatus!)
        : exitCode ?? -1,
    stdout: out.text,
    stderr: text,
    pid: process.pid,
    signaledPids: signaled,
    survivors: survivors.toList()..sort(),
    settlementProblem: settlementProblem,
    inputProblem: inputProblem,
    transportProblem: duplex?.problem,
  );
  duplex?._outputClosed();
  duplex?._settled.complete(result);
  return result;
}

// Protocol v1 owned leader: see ADR 0066 and bounded_session_protocol.dart.
// [singleProcessSession] has no separate leader — it execs in place (unchanged).
const _singleProcessSessionLaunch = r'''
my $marker = shift @ARGV;
select STDERR; $| = 1;
my $sid = POSIX::setsid();
if ($sid < 0) {
  print STDERR "$marker:error:setsid: $!\n"; exit 127;
}
print STDERR "$marker:ready:$sid\n";
print STDERR "$marker:started\n";
exec { $ARGV[0] } @ARGV;
print STDERR "target exec failed: $!\n";
exit 127;
''';

int _byteSequenceIndex(List<int> bytes, List<int> needle) {
  outer:
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

final _ownedProcessGroups = <int, _OwnedProcessGroup>{};

/// Non-zero while [_stopOwnedProcessGroup] is on the stack (`@visibleForTesting`).
@visibleForTesting
int ownedGroupStopInProgress = 0;

/// Incremented at the start of each [_stopOwnedProcessGroupBody] (`@visibleForTesting`).
@visibleForTesting
int ownedGroupStopPass = 0;

final class _OwnedProcessGroup {
  _OwnedProcessGroup(
    this.process, {
    required this.marker,
    this.controlBinding,
    required this.tightDeadline,
  }) : deadlineArmed = tightDeadline;

  final Process process;
  final String marker;
  final _SessionControlBinding? controlBinding;
  Socket? controlSocket;
  IOSink? controlSink;
  bool ready = false;
  bool rootExited = false;
  bool externallyStopped = false;
  bool groupGone = false;
  bool deferSigkillEscalation = false;
  bool clearedPsObservationStop = false;
  bool settleRequested = false;
  final bool tightDeadline;
  bool deadlineArmed;
  final settleAcknowledged = Completer<void>();

  bool get _deadlineBlocksSettle => tightDeadline && deadlineArmed;
  int? reportedWaitStatus;
  String? unsettledReason;
  String? controlFailure;

  /// Last successful `ps` observation of the owned group (empty included).
  final Set<int> observedMembers = <int>{};

  Future<void> disposeControl() async {
    try {
      await controlSink?.close();
    } on Object {
      // Best-effort.
    }
    try {
      await controlSocket?.close();
    } on Object {
      // Best-effort.
    }
    await controlBinding?.dispose();
  }
}

/// The launch acknowledgement proves setsid returned the root PID. POSIX
/// forbids joining a group from another session; live PGID membership therefore
/// stays inside that acknowledged session even where ps cannot expose its SID.
/// Other actors and descendants creating a new group/session are not signaled.
Future<Set<int>?> _ownedGroupMembers(_OwnedProcessGroup owned) async {
  if (owned.groupGone) return <int>{};
  final rows = await _groupRows();
  if (rows == null) return null;
  final members = <int>{
    for (final (pid, _, group, stat) in rows)
      if (owned.ready &&
          group == owned.process.pid &&
          !stat.contains('Z'))
        pid,
  };
  if (owned.ready && owned.rootExited && members.isEmpty) {
    // Once the admitted group disappears, never reacquire a recycled ID.
    owned.groupGone = true;
  }
  owned.observedMembers
    ..clear()
    ..addAll(members);
  return members;
}

Future<List<int>> _stopOwnedProcessGroup(
  _OwnedProcessGroup owned, {
  required Duration grace,
}) async {
  ownedGroupStopInProgress++;
  try {
    return await _stopOwnedProcessGroupBody(owned, grace: grace);
  } finally {
    ownedGroupStopInProgress--;
  }
}

Future<List<int>> _stopOwnedProcessGroupBody(
  _OwnedProcessGroup owned, {
  required Duration grace,
}) async {
  ownedGroupStopPass++;
  final signaled = <int>{};
  Future<bool> signal(ProcessSignal value) async {
    final snapshot = Set<int>.from(owned.observedMembers);
    final members = await _ownedGroupMembers(owned);
    final command = value == ProcessSignal.sigkill ? 'kill' : 'term';
    if (members == null) {
      // Unavailable observation is not death certification (ADR 0066).
      if (owned.rootExited) return false;
      if (snapshot.isEmpty) return false;
      if (owned.ready && owned.clearedPsObservationStop) return false;
      signaled.addAll(snapshot);
      if (!owned.rootExited && await _sendOwnedControl(owned, command)) {
        return true;
      }
      return false;
    }
    if (members.isEmpty) {
      // Cleared observation with a live supervisor is not group death (ADR 0066).
      if (!owned.ready && !owned.rootExited) {
        if (owned.process.kill(value)) signaled.add(owned.process.pid);
      } else if (!owned.rootExited && snapshot.isNotEmpty) {
        signaled.addAll(snapshot);
        owned.clearedPsObservationStop = true;
        owned.deferSigkillEscalation = true;
        return true;
      }
      return signaled.isNotEmpty;
    }
    if (value == ProcessSignal.sigkill &&
        await _onlyLeaderRemainsLive(members, owned)) {
      return signaled.isNotEmpty;
    }
    signaled.addAll(members);
    if (!owned.rootExited && await _sendOwnedControl(owned, command)) {
      return true;
    }
    if (owned.rootExited) return false;
    if (!owned.ready) {
      if (owned.process.kill(value)) signaled.add(owned.process.pid);
      return true;
    }
    return false;
  }

  await signal(ProcessSignal.sigterm);
  var end = DateTime.now().add(grace);
  while (DateTime.now().isBefore(end)) {
    final members = await _ownedGroupMembers(owned);
    if (members != null && members.isEmpty && owned.rootExited) {
      return signaled.toList()..sort();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (!owned.clearedPsObservationStop) {
    await signal(ProcessSignal.sigkill);
  }
  end = DateTime.now().add(grace);
  while (DateTime.now().isBefore(end)) {
    if (owned.rootExited) break;
    final alive = await _pidAlive(owned.process.pid);
    if (alive == false) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (!owned.rootExited) {
    final members = await _ownedGroupMembers(owned);
    final snapshot = Set<int>.from(owned.observedMembers);
    final refuseRootKill = owned.clearedPsObservationStop ||
        members == null && snapshot.isEmpty ||
        (members != null && members.isEmpty && owned.ready) ||
        (members == null && owned.ready);
    if (!refuseRootKill && owned.process.kill(ProcessSignal.sigkill)) {
      signaled.add(owned.process.pid);
    }
  }
  return signaled.toList()..sort();
}

/// When set, replaces live owned-group `ps` enumeration and the pre-spawn
/// `runBounded` observation probe for the whole isolate (`@visibleForTesting`).
@visibleForTesting
Future<List<(int, int, int, String)>?> Function()? boundedProcessGroupRowsOverride;

/// Live `ps` read without applying [boundedProcessGroupRowsOverride].
@visibleForTesting
Future<List<(int, int, int, String)>?> probeBoundedProcessGroupRows() =>
    _readGroupRowsFromPs();

/// Last successful `ps` observation for an admitted root (testing only).
@visibleForTesting
Set<int>? boundedProcessObservedMembersForRoot(int rootPid) =>
    _ownedProcessGroups[rootPid]?.observedMembers.toSet();

/// Stops an admitted [runBounded] POSIX session registered at [rootPid].
///
/// Refuses (returns `[]` without signaling) when no owned registration exists
/// — never guesses a process tree on a possibly recycled pid.
Future<List<int>> stopOwnedGroup(
  int rootPid, {
  Duration grace = const Duration(seconds: 5),
}) async {
  final owned = _ownedProcessGroups[rootPid];
  if (owned == null) return const [];
  owned.externallyStopped = true;
  return _stopOwnedProcessGroup(owned, grace: grace);
}

Future<List<(int, int, int, String)>?> _groupRows() async {
  final override = boundedProcessGroupRowsOverride;
  if (override != null) return override();
  return _readGroupRowsFromPs();
}

Future<List<(int, int, int, String)>?> _readGroupRowsFromPs() async {
  final output = await _runPsObservation(
    const ['-eo', 'pid=,ppid=,pgid=,stat='],
  );
  if (output == null) return null;
  final rows = <(int, int, int, String)>[];
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 4 || parts[3].startsWith('Z')) continue;
    final values = [for (final value in parts.take(3)) int.tryParse(value)];
    if (values.any((value) => value == null)) continue;
    rows.add((values[0]!, values[1]!, values[2]!, parts[3]));
  }
  return rows;
}

/// The run's terminal cause from the deadline flag and the exit code.
@visibleForTesting
BoundedProcessCause deadlineCause({
  required bool fired,
  required int exitCode,
}) => fired
    ? BoundedProcessCause.killedOnDeadline
    : exitCode < 0
    ? BoundedProcessCause.signaled
    : BoundedProcessCause.exited;

/// Stops a process tree rooted at [rootPid]: enumerate (`ps`, BEFORE the
/// first signal), TERM, wait up to [grace] while verifying death, then
/// re-enumerate and KILL whatever remains. Returns every pid signaled,
/// so callers can verify death themselves.
Future<List<int>> stopProcessTree(
  int rootPid, {
  Duration grace = const Duration(seconds: 5),
}) async {
  final owned = _ownedProcessGroups[rootPid];
  if (owned != null) {
    owned.externallyStopped = true;
    return _stopOwnedProcessGroup(owned, grace: grace);
  }
  return const [];
}

/// Legacy `ps` tree stop for processes **not** admitted by [runBounded].
@visibleForTesting
Future<List<int>> stopUnownedPosixProcessTree(
  int rootPid, {
  Duration grace = const Duration(seconds: 5),
}) async {
  final signaled = <int>{...await _processTree(rootPid)};
  _signalAll(signaled, ProcessSignal.sigterm);
  final graceEnd = DateTime.now().add(grace);
  var alive = await _stillAlive(signaled);
  while (alive.isNotEmpty && DateTime.now().isBefore(graceEnd)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    alive = await _stillAlive(signaled);
  }
  if (alive.isEmpty) return signaled.toList()..sort();
  final beforeKill = <int>{...signaled, ...await _processTree(rootPid)};
  _signalAll(beforeKill, ProcessSignal.sigkill);
  final killEnd = DateTime.now().add(grace);
  var remaining = await _stillAlive(beforeKill);
  while (remaining.isNotEmpty && DateTime.now().isBefore(killEnd)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    remaining = await _stillAlive(beforeKill);
  }
  return beforeKill.toList()..sort();
}

/// The tree under [rootPid] (inclusive), from one `ps` snapshot. On
/// Windows (no `ps`) the tree degrades to the root pid alone — the
/// recorded `taskkill /T` follow-up; named, not silent.
Future<Set<int>> _processTree(int rootPid) async {
  final rows = await _psRows();
  if (rows == null) return {rootPid};
  final children = <int, List<int>>{};
  for (final (pid, ppid, _) in rows) {
    children.putIfAbsent(ppid, () => []).add(pid);
  }
  final tree = <int>{rootPid};
  final queue = <int>[rootPid];
  while (queue.isNotEmpty) {
    for (final child in children[queue.removeLast()] ?? const <int>[]) {
      if (tree.add(child)) queue.add(child);
    }
  }
  return tree;
}

/// `(pid, ppid, stat)` rows from one `ps` snapshot; zombies (`Z*`) are
/// excluded — a dead-but-unreaped pid is NOT alive. Null when `ps` is
/// unavailable (Windows).
Future<List<(int, int, String)>?> _psRows() async {
  final output = await _runPsObservation(const ['-eo', 'pid=,ppid=,stat=']);
  if (output == null) return null;
  final rows = <(int, int, String)>[];
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final pid = int.tryParse(parts[0]);
    final ppid = int.tryParse(parts[1]);
    if (pid == null || ppid == null) continue;
    final stat = parts.length >= 3 ? parts[2] : '';
    if (stat.startsWith('Z')) continue;
    rows.add((pid, ppid, stat));
  }
  return rows;
}

Future<String?> _runPsObservation(
  List<String> args, {
  Duration budget = _groupObservationBudget,
}) async {
  Process? process;
  try {
    process = await Process.start('ps', args);
    final stdoutFuture = process.stdout.fold<List<int>>(
      <int>[],
      (previous, chunk) => [...previous, ...chunk],
    );
    final exitCode = await process.exitCode.timeout(
      budget,
      onTimeout: () {
        process!.kill(ProcessSignal.sigkill);
        return -999;
      },
    );
    if (exitCode == -999 || exitCode != 0) {
      process.kill(ProcessSignal.sigkill);
      return null;
    }
    final buffer = await stdoutFuture;
    return utf8.decode(buffer, allowMalformed: true);
  } on Object {
    process?.kill(ProcessSignal.sigkill);
    return null;
  }
}

void _signalAll(Iterable<int> pids, ProcessSignal signal) {
  for (final pid in pids) {
    try {
      Process.killPid(pid, signal);
    } on Object {
      // Already reaped or not ours — the liveness polls decide, not the
      // signal call.
    }
  }
}

/// True / false / null (probe unavailable on this platform).
Future<bool?> _pidAlive(int pid) async {
  final rows = await _psRows();
  if (rows == null) return null;
  return rows.any((row) => row.$1 == pid);
}

Future<Set<int>> _stillAlive(Iterable<int> pids) async {
  final rows = await _psRows();
  if (rows == null) return pids.toSet(); // unprobeable: report, never guess
  final live = rows.map((row) => row.$1).toSet();
  return pids.toSet().intersection(live);
}

/// Retain ownership of reported survivors until observation proves settlement.
/// This is a read-only wait, never another signal against a possibly reused
/// identity. Unavailable observation cannot certify death.
Future<void> awaitProcessSettlement(
  Iterable<int> ownedPids, {
  Duration budget = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(budget);
  var remaining = ownedPids.toSet();
  while (remaining.isNotEmpty && DateTime.now().isBefore(end)) {
    final rows = await _psRows();
    if (rows == null) return;
    final live = rows.map((row) => row.$1).toSet();
    remaining = remaining.intersection(live);
    if (remaining.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// Bounded byte capture (tail kept): output is evidence, not a side
/// channel.
final class _BoundedCapture {
  _BoundedCapture(this.maxBytes);

  final int maxBytes;
  final _chunks = <List<int>>[];
  var _length = 0;
  var _dropped = 0;

  void add(List<int> chunk) {
    _chunks.add(chunk);
    _length += chunk.length;
    while (_length > maxBytes && _chunks.isNotEmpty) {
      final head = _chunks.first;
      final cut = head.length <= _length - maxBytes
          ? head.length
          : _length - maxBytes;
      if (cut >= head.length) {
        _chunks.removeAt(0);
      } else {
        _chunks[0] = head.sublist(cut);
      }
      _length -= cut;
      _dropped += cut;
    }
  }

  String get text {
    final body = utf8.decode([
      for (final chunk in _chunks) ...chunk,
    ], allowMalformed: true);
    return _dropped > 0 ? '[…$_dropped bytes dropped] $body' : body;
  }
}
