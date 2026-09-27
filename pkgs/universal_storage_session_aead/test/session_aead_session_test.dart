import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_session_aead/universal_storage_session_aead.dart';

// Test controllers stay open for the whole test run so the wiretap can be
// inspected at any point; the process teardown closes them.
// ignore_for_file: close_sinks

/// Paired recording transports: every frame that crosses the wire is kept
/// for inspection, and tests can inject raw bytes as if the wire emitted
/// them (replay/forgery attempts).
final class _WiretapPair {
  factory _WiretapPair.paired({
    final String a = 'device-a',
    final String b = 'device-b',
  }) {
    final sideA = _WiretapTransport(a);
    final sideB = _WiretapTransport(b);
    sideA._remote = sideB;
    sideB._remote = sideA;
    return _WiretapPair._(sideA, sideB);
  }

  _WiretapPair._(this.a, this.b);

  final _WiretapTransport a;
  final _WiretapTransport b;
}

final class _WiretapTransport implements MeshTransport {
  _WiretapTransport(this.selfId);

  final String selfId;

  _WiretapTransport? _remote;

  /// Frames this side put on the wire, in order.
  final List<Uint8List> outbound = <Uint8List>[];

  final _incoming = StreamController<MeshSession>();

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final remote = _remote;
    if (remote == null || remote.selfId != peer.peerId) {
      throw MeshConnectionException(peer.peerId, 'not linked');
    }
    final initiatorIn = StreamController<Uint8List>();
    final responderIn = StreamController<Uint8List>();
    final initiator = _WiretapSession(
      peer.peerId,
      initiatorIn,
      (final bytes) {
        outbound.add(bytes);
        responderIn.add(bytes);
      },
    );
    final responder = _WiretapSession(
      selfId,
      responderIn,
      (final bytes) {
        remote.outbound.add(bytes);
        initiatorIn.add(bytes);
      },
    );
    scheduleMicrotask(() => remote._incoming.add(responder));
    return initiator;
  }
}

final class _WiretapSession implements MeshSession {
  _WiretapSession(this.remotePeerId, this._inbound, this._onSend);

  @override
  final String remotePeerId;

  final StreamController<Uint8List> _inbound;
  final void Function(Uint8List) _onSend;

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Future<void> send(final Uint8List payload) async => _onSend(payload);

  @override
  Future<void> close() async => unawaited(_inbound.close());

  /// Pushes raw bytes onto the inbound stream as if the wire emitted them.
  void inject(final Uint8List bytes) => _inbound.add(bytes);
}

Future<({SimpleKeyPair identity, Uint8List publicKey})> _identity() async {
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  return (identity: keyPair, publicKey: Uint8List.fromList(publicKey.bytes));
}

MeshPeerRecord _recordOf(final String id, final List<int> key) =>
    MeshPeerRecord(peerId: id, displayName: id, identityKey: key);

void main() {
  test('pinned handshake seals both directions; wire never shows plaintext',
      () async {
    final a = await _identity();
    final b = await _identity();
    final pair = _WiretapPair.paired();

    final accepted = Completer<SessionAeadSession>();
    pair.b.incoming.listen((final raw) async {
      try {
        accepted.complete(
          await SessionAeadSession.accept(
            raw: raw,
            identityKeyPair: b.identity,
            selfId: 'device-b',
            pinnedIdentityKeys: {'device-a': a.publicKey},
          ),
        );
      } on Object catch (error) {
        accepted.completeError(error);
      }
    });

    final dialer = await SessionAeadSession.start(
      raw: await pair.a.connect(_recordOf('device-b', b.publicKey)),
      identityKeyPair: a.identity,
      selfId: 'device-a',
      remotePeerId: 'device-b',
      expectedPeerIdentityKey: b.publicKey,
    );
    final host = await accepted.future;

    expect(dialer.remotePeerId, 'device-b');
    expect(host.remotePeerId, 'device-a');
    expect(dialer.trustedByPinnedKey, isTrue);
    expect(host.trustedByPinnedKey, isTrue);

    // Exactly 3 handshake messages crossed the wire.
    final handshakeFrames =
        pair.a.outbound.length + pair.b.outbound.length;
    expect(handshakeFrames, 3);

    final payload = Uint8List.fromList(utf8.encode('gesture 0.42 0.17'));
    final received = Completer<Uint8List>();
    host.inbound.listen(received.complete);
    await dialer.send(payload);
    expect(await received.future, payload);

    final replyReceived = Completer<Uint8List>();
    dialer.inbound.listen(replyReceived.complete);
    await host.send(Uint8List.fromList(utf8.encode('ack')));
    expect(await replyReceived.future, utf8.encode('ack'));

    // The wire saw M1, M2, M3, and two sealed frames — never plaintext.
    final allFrames = [...pair.a.outbound, ...pair.b.outbound];
    expect(allFrames.length, 5);
    final plaintext = utf8.encode('gesture 0.42 0.17');
    for (final frame in allFrames) {
      expect(
        _contains(frame, plaintext),
        isFalse,
        reason: 'plaintext leaked on the wire',
      );
    }
  });

  test('forged initiator identity fails the responder transcript check',
      () async {
    final a = await _identity(); // the pinned, impersonated peer
    final b = await _identity(); // honest host
    final c = await _identity(); // impostor's key
    final pair = _WiretapPair.paired(b: 'host');

    final accepted = Completer<SessionAeadSession>();
    pair.b.incoming.listen((final raw) async {
      try {
        accepted.complete(
          await SessionAeadSession.accept(
            raw: raw,
            identityKeyPair: b.identity,
            selfId: 'host',
            pinnedIdentityKeys: {'device-a': a.publicKey},
          ),
        );
      } on Object catch (error) {
        accepted.completeError(error);
      }
    });

    // The impostor CLAIMS device-a but signs with C's key.
    await expectLater(
      SessionAeadSession.start(
        raw: await pair.a.connect(_recordOf('host', b.publicKey)),
        identityKeyPair: c.identity,
        selfId: 'device-a',
        remotePeerId: 'host',
        expectedPeerIdentityKey: b.publicKey,
      ),
      completes,
    );
    await expectLater(
      accepted.future,
      throwsA(isA<SessionHandshakeException>()),
    );
  });

  test('strict responder rejects unknown peers before revealing anything',
      () async {
    final a = await _identity();
    final pair = _WiretapPair.paired(a: 'device-z', b: 'host');

    final accepted = Completer<SessionAeadSession>();
    pair.b.incoming.listen((final raw) async {
      try {
        accepted.complete(
          await SessionAeadSession.accept(
            raw: raw,
            identityKeyPair: a.identity,
            selfId: 'host',
            // Explicit: strictness is the point of this test.
            // ignore: avoid_redundant_argument_values
            trustOnFirstUse: false,
          ),
        );
      } on Object catch (error) {
        accepted.completeError(error);
      }
    });

    final dialerRaw = await pair.a.connect(_recordOf('host', const <int>[]));
    final dialer = SessionAeadSession.start(
      raw: dialerRaw,
      identityKeyPair: a.identity,
      selfId: 'device-z',
      remotePeerId: 'host',
      trustOnFirstUse: true,
    );

    await expectLater(
      accepted.future,
      throwsA(isA<SessionHandshakeException>()),
    );
    // Nothing was revealed to the unknown peer before the rejection.
    expect(pair.b.outbound, isEmpty);

    // Closing the raw session surfaces the rejection on the dialer too.
    await dialerRaw.close();
    await expectLater(dialer, throwsA(isA<SessionHandshakeException>()));
  });

  test('TOFU binds a verified key on first contact', () async {
    final a = await _identity();
    final b = await _identity();
    final pair = _WiretapPair.paired();

    final accepted = Completer<SessionAeadSession>();
    pair.b.incoming.listen((final raw) async {
      accepted.complete(
        await SessionAeadSession.accept(
          raw: raw,
          identityKeyPair: b.identity,
          selfId: 'device-b',
          trustOnFirstUse: true,
        ),
      );
    });

    final dialer = await SessionAeadSession.start(
      raw: await pair.a.connect(_recordOf('device-b', const <int>[])),
      identityKeyPair: a.identity,
      selfId: 'device-a',
      remotePeerId: 'device-b',
      // Explicit: the dialer learns the host key from the ride-along.
      // ignore: avoid_redundant_argument_values
      trustOnFirstUse: true,
    );
    final host = await accepted.future;

    expect(host.trustedByPinnedKey, isFalse);
    expect(host.remoteIdentityKey, a.publicKey);
    expect(dialer.trustedByPinnedKey, isFalse);
    expect(dialer.remoteIdentityKey, b.publicKey);

    // The learned key authenticates traffic both ways.
    final received = Completer<Uint8List>();
    host.inbound.listen(received.complete);
    await dialer.send(Uint8List.fromList(utf8.encode('tofu works')));
    expect(await received.future, utf8.encode('tofu works'));
  });

  test('a replayed sealed record drops without disturbing the stream',
      () async {
    final a = await _identity();
    final b = await _identity();
    final pair = _WiretapPair.paired();

    final accepted = Completer<SessionAeadSession>();
    late final _WiretapSession rawResponder;
    pair.b.incoming.listen((final raw) async {
      rawResponder = raw as _WiretapSession;
      accepted.complete(
        await SessionAeadSession.accept(
          raw: raw,
          identityKeyPair: b.identity,
          selfId: 'device-b',
          pinnedIdentityKeys: {'device-a': a.publicKey},
        ),
      );
    });

    final dialer = await SessionAeadSession.start(
      raw: await pair.a.connect(_recordOf('device-b', b.publicKey)),
      identityKeyPair: a.identity,
      selfId: 'device-a',
      remotePeerId: 'device-b',
      expectedPeerIdentityKey: b.publicKey,
    );
    final host = await accepted.future;

    final received = <Uint8List>[];
    host.inbound.listen(received.add);
    final payload = Uint8List.fromList(utf8.encode('one'));
    await dialer.send(payload);
    await _pump();
    expect(received, [payload]);

    // Replay the SAME sealed frame off the wire: dropped as named data.
    final sealedFrame = pair.a.outbound.last;
    rawResponder.inject(sealedFrame);
    await _pump();
    expect(host.droppedInboundCount, 1);

    // The channel is unharmed: the next fresh frame still arrives.
    final second = Uint8List.fromList(utf8.encode('two'));
    await dialer.send(second);
    await _pump();
    expect(received, [payload, second]);
    expect(host.droppedInboundCount, 1);
  });

  test('SessionAeadTransport wraps a raw transport end to end', () async {
    final a = await _identity();
    final b = await _identity();
    final pair = _WiretapPair.paired();

    final transportA = SessionAeadTransport(
      inner: pair.a,
      identityKeyPair: a.identity,
      selfId: 'device-a',
      pinnedIdentityKeys: {'device-b': b.publicKey},
    );
    final transportB = SessionAeadTransport(
      inner: pair.b,
      identityKeyPair: b.identity,
      selfId: 'device-b',
      pinnedIdentityKeys: {'device-a': a.publicKey},
    );

    final inboundB = Completer<MeshSession>();
    transportB.incoming.listen(inboundB.complete);

    final sessionA = await transportA
        .connect(_recordOf('device-b', b.publicKey));
    expect(sessionA, isA<SessionAeadSession>());
    final sessionB = await inboundB.future;
    expect(sessionB.remotePeerId, 'device-a');

    final received = Completer<Uint8List>();
    sessionB.inbound.listen(received.complete);
    await sessionA.send(Uint8List.fromList(utf8.encode('via wrapper')));
    expect(await received.future, utf8.encode('via wrapper'));

    await sessionA.close();
    await sessionB.close();
    await transportA.dispose();
    await transportB.dispose();
  });

  test(
      'wrapper surfaces handshake failure and keeps accepting afterwards',
      () async {
    final a = await _identity();
    final b = await _identity();
    final pair = _WiretapPair.paired();

    final failures = <Object>[];
    // Strict, NO pins: dialing device-b fails on the initiator side
    // because the record carries no identity key and nothing is pinned.
    final strictA = SessionAeadTransport(
      inner: pair.a,
      identityKeyPair: a.identity,
      selfId: 'device-a',
      onHandshakeFailure: (final _, final error, final _) =>
          failures.add(error),
    );
    final pinnedB = SessionAeadTransport(
      inner: pair.b,
      identityKeyPair: b.identity,
      selfId: 'device-b',
      pinnedIdentityKeys: {'device-a': a.publicKey},
    );
    final inboundB = Completer<MeshSession>();
    pinnedB.incoming.listen(inboundB.complete);

    await expectLater(
      strictA.connect(_recordOf('device-b', const <int>[])),
      throwsA(isA<SessionHandshakeException>()),
    );
    expect(failures, hasLength(1));
    expect(failures.single, isA<SessionHandshakeException>());

    // Pinning the peer makes the same dial succeed; the wrapper is
    // unharmed by the earlier failure.
    final transportA = SessionAeadTransport(
      inner: pair.a,
      identityKeyPair: a.identity,
      selfId: 'device-a',
      pinnedIdentityKeys: {'device-b': b.publicKey},
    );
    final sessionA = await transportA
        .connect(_recordOf('device-b', b.publicKey));
    final sessionB = await inboundB.future;
    expect(sessionB.remotePeerId, 'device-a');

    await sessionA.close();
    await sessionB.close();
    await strictA.dispose();
    await transportA.dispose();
    await pinnedB.dispose();
  });
}

bool _contains(final List<int> haystack, final List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
