import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Runs the wire's Ed25519 sign/verify on a background isolate.
///
/// Measured on a Snapdragon-class phone (debug build): one pure-Dart
/// `Ed25519.sign` costs ~390 ms. Executed on the caller's isolate that
/// blocks the event loop for the duration — at camera rate the landmark
/// stream to the UI falls seconds behind (skeleton freezes, then drains in
/// bursts). Both wrappers keep the upstream contracts
/// ([EphemeralFrameSigner] / [EphemeralFrameAuthenticator]) but run the
/// math on a worker isolate that kills itself after an idle timeout, so
/// short-lived transports never leak it.
final class IsolateFrameSigner
    implements EphemeralFrameSigner, EphemeralFrameIdentityPublisher {
  IsolateFrameSigner._(this._seed, this._publicKey);

  final Uint8List _seed;
  final Uint8List? _publicKey;

  ReceivePort? _replyPort;
  Future<SendPort>? _spawning;
  final Map<int, Completer<Uint8List>> _pending = <int, Completer<Uint8List>>{};
  int _nextRequestId = 0;

  static Future<IsolateFrameSigner> spawn(final SimpleKeyPair keyPair) async {
    final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
    final publicKey = Uint8List.fromList(
      (await keyPair.extractPublicKey()).bytes,
    );
    return IsolateFrameSigner._(seed, publicKey);
  }

  @override
  Future<Uint8List> sign(final MeshEphemeralFrame frame) async {
    // The canonical signing input is computed here (cheap); only the
    // Ed25519 math runs on the worker.
    final input = frame.signingInput();
    final workerPort = await _ensureWorker();
    final requestId = _nextRequestId++;
    final request = Completer<Uint8List>();
    _pending[requestId] = request;
    workerPort.send((requestId, _replyPort!.sendPort, input));
    return request.future;
  }

  @override
  Future<List<int>?> identityKeyForPayload() =>
      Future<List<int>?>.value(_publicKey);

  Future<SendPort> _ensureWorker() => _spawning ??= _spawnWorker();

  Future<SendPort> _spawnWorker() async {
    final ready = Completer<SendPort>();
    final replyPort = ReceivePort();
    late final StreamSubscription<Object?> subscription;
    subscription = replyPort.listen((final message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final (requestId, signature) = message as (int, Uint8List?);
      final completer = _pending.remove(requestId);
      if (completer == null) return;
      if (signature == null) {
        completer.completeError(StateError('background signing failed'));
      } else {
        completer.complete(signature);
      }
    });
    try {
      await Isolate.spawn(
        _signerWorkerMain,
        (replyPort.sendPort, _seed),
        debugName: 'vosges-frame-signer',
      );
      _replyPort = replyPort;
      // No idle timer: the isolate parks on its ReceivePort (~0 CPU), and
      // killing it on a timer risks racing an in-flight send.
      // Awaited so a worker that dies before its first hello runs the
      // catch below (cancel ports, clear the spawn cache).
      return await ready.future;
    } on Object catch (error, stackTrace) {
      subscription.cancel();
      replyPort.close();
      _spawning = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// Top-level worker: rebuilds the keypair from the seed once, then signs
/// canonical signing inputs forever.
Future<void> _signerWorkerMain((SendPort, Uint8List) init) async {
  final (replyPort, seed) = init;
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final workerPort = ReceivePort();
  replyPort.send(workerPort.sendPort);
  await for (final message in workerPort) {
    final (requestId, callerReply, input) =
        message as (int, SendPort, Uint8List);
    try {
      final signature = await Ed25519().sign(input, keyPair: keyPair);
      callerReply.send((requestId, Uint8List.fromList(signature.bytes)));
    } on Object {
      // Failure envelope: null signature; the caller completes with an
      // error so the transport surfaces it like a local failure.
      callerReply.send((requestId, null));
    }
  }
}

/// Background-isolate variant of [MeshFrameAuthenticator] for receivers:
/// every inbound frame is verified with the same slow pure-Dart Ed25519,
/// which is the desktop twin of the sender-side lag.
final class IsolateFrameAuthenticator implements EphemeralFrameAuthenticator {
  IsolateFrameAuthenticator._(this._identityKeys);

  final Map<String, List<int>> _identityKeys;

  ReceivePort? _replyPort;
  Future<SendPort>? _spawning;
  final Map<int, Completer<bool>> _pending = <int, Completer<bool>>{};
  int _nextRequestId = 0;

  static Future<IsolateFrameAuthenticator> spawn(
    final Map<String, List<int>> identityKeys,
  ) async => IsolateFrameAuthenticator._(
    identityKeys.map((final k, final v) => MapEntry(k, List<int>.of(v))),
  );

  @override
  Future<bool> verify(final MeshEphemeralFrame frame) async {
    final workerPort = await _ensureWorker();
    final requestId = _nextRequestId++;
    final request = Completer<bool>();
    _pending[requestId] = request;
    workerPort.send((requestId, _replyPort!.sendPort, frame));
    return request.future;
  }

  Future<SendPort> _ensureWorker() => _spawning ??= _spawnWorker();

  Future<SendPort> _spawnWorker() async {
    final ready = Completer<SendPort>();
    final replyPort = ReceivePort();
    late final StreamSubscription<Object?> subscription;
    subscription = replyPort.listen((final message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final (requestId, verified) = message as (int, bool);
      _pending.remove(requestId)?.complete(verified);
    });
    try {
      await Isolate.spawn(
        _authenticatorWorkerMain,
        (replyPort.sendPort, _identityKeys),
        debugName: 'vosges-frame-authenticator',
      );
      _replyPort = replyPort;
      // Awaited so a worker that dies before its first hello runs the
      // catch below (cancel ports, clear the spawn cache).
      return await ready.future;
    } on Object catch (error, stackTrace) {
      subscription.cancel();
      replyPort.close();
      _spawning = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// Top-level worker for verification.
Future<void> _authenticatorWorkerMain(
  (SendPort, Map<String, List<int>>) init,
) async {
  final (replyPort, identityKeys) = init;
  final authenticator = MeshFrameAuthenticator(
    identityKeys: identityKeys.map(
      (final k, final v) => MapEntry(k, Uint8List.fromList(v)),
    ),
    trustOnFirstUse: false,
  );
  final workerPort = ReceivePort();
  replyPort.send(workerPort.sendPort);
  await for (final message in workerPort) {
    final (requestId, callerReply, frame) =
        message as (int, SendPort, MeshEphemeralFrame);
    try {
      callerReply.send((requestId, await authenticator.verify(frame)));
    } on Object {
      callerReply.send((requestId, false));
    }
  }
}
