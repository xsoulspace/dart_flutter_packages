part of 'bounded_process.dart';

/// Supported owned-session supervisor protocol revision.
const _sessionProtocolVersion = '1';

/// Wall-clock budget for each live `ps` enumeration.
const _groupObservationBudget = Duration(seconds: 2);

final class _SessionControlBinding {
  _SessionControlBinding({
    required this.directory,
    required this.socketPath,
    required this.server,
    required this.firstConnection,
  });

  final Directory directory;
  final String socketPath;
  final ServerSocket server;

  /// Subscribed at bind time so a fast leader connect is never dropped.
  final Future<Socket> firstConnection;

  static Future<_SessionControlBinding?> bind() async {
    try {
      final directory = await Directory.systemTemp.createTemp('bounded-p1-');
      await Process.run('chmod', ['700', directory.path]);
      final socketPath = '${directory.path}/control.sock';
      final server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      return _SessionControlBinding(
        directory: directory,
        socketPath: socketPath,
        server: server,
        firstConnection: server.first,
      );
    } on Object {
      return null;
    }
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

Future<Socket?> _acceptSessionControl(_SessionControlBinding binding) async {
  try {
    return await binding.firstConnection.timeout(const Duration(seconds: 30));
  } on Object {
    return null;
  }
}

Future<void> _listenSessionControl(
  _OwnedProcessGroup owned,
  Completer<void> channelStarted,
  Completer<void> startup, {
  required String marker,
}) async {
  final socket = owned.controlSocket;
  if (socket == null) return;
  final buffer = <int>[];
  var authenticated = false;
  try {
    await for (final chunk in socket) {
      buffer.addAll(chunk);
      while (true) {
        final index = buffer.indexOf(10);
        if (index < 0) break;
        final line = utf8.decode(
          buffer.sublist(0, index),
          allowMalformed: true,
        );
        buffer.removeRange(0, index + 1);
        if (!authenticated) {
          if (line != marker) {
            owned.controlFailure = 'owned session control authentication failed';
            if (!startup.isCompleted) startup.complete();
            if (!channelStarted.isCompleted) channelStarted.complete();
            return;
          }
          authenticated = true;
          continue;
        }
        _handleSessionControlLine(owned, line, channelStarted, startup);
      }
    }
  } on Object {
    // Socket closed; leader may still be winding down.
  }
}

void _handleSessionControlLine(
  _OwnedProcessGroup owned,
  String line,
  Completer<void> channelStarted,
  Completer<void> startup,
) {
  if (line == 'started') {
    if (!channelStarted.isCompleted) channelStarted.complete();
    if (!startup.isCompleted) startup.complete();
    return;
  }
  if (line == 'settled') {
    if (!owned.settleAcknowledged.isCompleted) {
      owned.settleAcknowledged.complete();
    }
    return;
  }
  if (line.startsWith('exit:')) {
    final value = int.tryParse(line.substring('exit:'.length));
    if (value != null) owned.reportedWaitStatus = value;
    unawaited(_maybeSettleAfterTargetExit(owned));
    return;
  }
  if (line.startsWith('unsettled:')) {
    owned.unsettledReason = line.substring('unsettled:'.length);
    return;
  }
}

Future<void> _maybeSettleAfterTargetExit(_OwnedProcessGroup owned) async {
  if (owned.externallyStopped ||
      owned.reportedWaitStatus == null ||
      owned.settleRequested ||
      owned._deadlineBlocksSettle) {
    return;
  }
  final members = await _ownedGroupMembers(owned);
  if (members == null) return;
  if (!await _onlyLeaderRemainsLive(members, owned)) return;
  await _requestSessionSettle(owned);
}

Future<bool> _onlyLeaderRemainsLive(
  Set<int> members,
  _OwnedProcessGroup owned,
) async {
  var liveLeader = false;
  for (final pid in members) {
    if (await _pidAlive(pid) == false) continue;
    if (pid != owned.process.pid) return false;
    liveLeader = true;
  }
  return liveLeader;
}

Future<void> _watchSessionSettle(_OwnedProcessGroup owned) async {
  while (!owned.settleRequested) {
    if (owned.externallyStopped) {
      return;
    }
    if (owned._deadlineBlocksSettle) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      continue;
    }
    final members = await _ownedGroupMembers(owned);
    if (members == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      continue;
    }
    if (owned.reportedWaitStatus != null &&
        await _onlyLeaderRemainsLive(members, owned)) {
      await _requestSessionSettle(owned);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _requestSessionSettle(_OwnedProcessGroup owned) async {
  if (owned.externallyStopped || owned.settleRequested) return;
  owned.settleRequested = true;
  await _sendOwnedControl(owned, 'settle');
}

Future<bool> _sendOwnedControl(_OwnedProcessGroup owned, String command) async {
  final sink = owned.controlSink;
  if (sink == null) return false;
  try {
    sink.writeln(command);
    await sink.flush();
    return true;
  } on Object {
    return false;
  }
}

int _waitStatusExitCode(int waitStatus) {
  if (waitStatus & 0x7f != 0) {
    return -(waitStatus & 0x7f);
  }
  return waitStatus >> 8;
}
