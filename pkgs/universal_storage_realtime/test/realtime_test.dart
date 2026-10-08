// The realtime plane's four semantics, proven one by one, then the whole
// shape driven with a VOSGES-SHAPED vocabulary (pointer frames droppable
// with x/y/confidence payloads, pinch edges reliable) — the adoption
// proof that an app brings only its schema.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_realtime/universal_storage_realtime.dart';

/// Polls a condition the fake transports settle asynchronously.
Future<void> _until(final bool Function() probe) async {
  for (var i = 0; i < 500; i++) {
    if (probe()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached within 5s');
}

void main() {
  test('the envelope roundtrips and the classifier claims only its plane',
      () {
    final envelope = RealtimeEnvelope(
      type: 'pointerMove',
      seq: 7,
      reliable: false,
      issuedAtMs: 42,
      payload: {'x': 0.5, 'y': 0.25, 'confidence': 0.9},
    );
    final decoded = RealtimeEnvelope.tryDecode(envelope.encode());
    expect(decoded, isNotNull);
    expect(decoded!.type, 'pointerMove');
    expect(decoded.seq, 7);
    expect(decoded.reliable, isFalse);
    expect(decoded.payload['confidence'], 0.9);

    expect(looksLikeRealtimeFrame(envelope.encode()), isTrue);
    // Foreign planes and garbage never claim the realtime plane.
    expect(
      looksLikeRealtimeFrame(
        Uint8List.fromList([1, 2, 3]),
      ),
      isFalse,
    );
    expect(
      looksLikeRealtimeFrame(
        Uint8List.fromList('{"type":"hello","v":2}'.codeUnits),
      ),
      isFalse,
    );
  });

  test('reliable sends dedupe replays on receipt', () async {
    final pair = FakeMeshPair.paired();
    final link = RealtimeLink(session: await pair.a.connect(const MeshPeerRecord(peerId: 'device-b', displayName: 'b')));
    final events = <String>[];
    link.inbound.listen((final e) => events.add('${e.type}#${e.envelope.seq}'));

    // Capture the session once: the fake's incoming is single-subscription
    // and `.first` consumes the listener.
    final otherSession = await pair.b.incoming.first;
    final other = RealtimeLink(session: otherSession);
    await other.sendReliable('pinchStart', {});
    await other.sendReliable('pinchStart', {}); // New seq: delivered.
    // A replayed frame with an OLD seq is dropped.
    await otherSession.send(
      RealtimeEnvelope(
        type: 'pinchStart',
        seq: 1,
        reliable: true,
        issuedAtMs: 0,
      ).encode(),
    );
    await other.sendReliable('pinchEnd', {});
    await pumpEventQueue();

    expect(events, ['pinchStart#1', 'pinchStart#2', 'pinchEnd#3']);
    await link.close();
    await other.close();
  });

  test('droppable sends coalesce: newest wins while one is in flight',
      () async {
    final releaseGates = <Completer<void>>[];
    final sentFrames = <Uint8List>[];
    final slowSession = _GatedSession(releaseGates, sentFrames);
    final link = RealtimeLink(session: slowSession);

    final first = link.sendDroppable('pointerMove', {'n': 1});
    // The first send parks on gate 1; these two must coalesce into ONE
    // pending frame without blocking the caller.
    unawaited(link.sendDroppable('pointerMove', {'n': 2}));
    final third = link.sendDroppable('pointerMove', {'n': 3});
    await pumpEventQueue();
    expect(sentFrames, hasLength(0), reason: 'the gate holds the send');
    expect(releaseGates, hasLength(1), reason: 'exactly one send in flight');

    releaseGates.removeAt(0).complete();
    await _until(() => sentFrames.isNotEmpty);
    expect(
      RealtimeEnvelope.tryDecode(sentFrames.first)!.payload['n'],
      1,
      reason: 'the in-flight frame goes first',
    );
    await pumpEventQueue();
    expect(releaseGates, hasLength(1), reason: 'the coalesced newest is in '
        'flight');

    releaseGates.removeAt(0).complete();
    await Future.wait([first, third]);
    expect(sentFrames, hasLength(2));
    expect(
      RealtimeEnvelope.tryDecode(sentFrames.last)!.payload['n'],
      3,
      reason: '2 and 3 coalesced into the newest',
    );
    await link.close();
  });

  test('heartbeats are auto-acked, never surfaced, and stale links die',
      () async {
    final pair = FakeMeshPair.paired();
    var stale = false;
    final link = RealtimeLink(
      session: await pair.a.connect(const MeshPeerRecord(peerId: 'device-b', displayName: 'b')),
      heartbeatInterval: const Duration(milliseconds: 15),
      staleAfter: const Duration(milliseconds: 40),
      onStale: (final reason) => stale = true,
    );
    final appEvents = <String>[];
    link.inbound.listen((final e) => appEvents.add(e.type));

    final other = RealtimeLink(
      session: await pair.b.incoming.first,
      heartbeatInterval: const Duration(milliseconds: 15),
      staleAfter: const Duration(milliseconds: 40),
    );
    final otherApp = <String>[];
    other.inbound.listen((final e) => otherApp.add(e.type));

    // Heartbeats flow; NEITHER side surfaces them as app events.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(appEvents, isEmpty);
    expect(otherApp, isEmpty);
    expect(stale, isFalse, reason: 'peers keep each other alive');

    // Silence the peer: the link dies and reports the reason.
    await other.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(stale, isTrue);
    await link.close();
  });

  test('tick-driven links own no timers; tick() heartbeats and stale-dies',
      () async {
    var now = DateTime.utc(2026, 9, 27, 12);
    final session = _RecordingSession();
    final sent = session.sent;
    var died = '';
    final link = RealtimeLink(
      session: session,
      heartbeatInterval: const Duration(seconds: 1),
      staleAfter: const Duration(seconds: 3),
      clock: () => now,
      tickDriven: true,
      onStale: (final reason) => died = reason,
    );

    // Real time passing decides NOTHING: no heartbeat, no death.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, isEmpty);
    expect(died, isEmpty);

    // A tick before the heartbeat is due sends nothing.
    now = now.add(const Duration(milliseconds: 500));
    await link.tick();
    expect(sent, isEmpty);

    // A tick past the interval sends exactly one heartbeat.
    now = now.add(const Duration(seconds: 1));
    await link.tick();
    expect(sent, hasLength(1));
    expect(
      RealtimeEnvelope.tryDecode(sent.single)!.type,
      RealtimeTypes.heartbeat,
    );
    await link.tick();
    expect(sent, hasLength(1), reason: 'not due again');

    // An inbound frame refreshes liveness (the tick heartbeat above does
    // NOT come back — the fake session is unlinked).
    now = now.add(const Duration(seconds: 2));
    session.receive(
      RealtimeEnvelope(
        type: 'app',
        seq: 1,
        reliable: true,
        issuedAtMs: 0,
      ).encode(),
    );
    await pumpEventQueue();
    expect(died, isEmpty);

    // Silence past the stale window dies on the next tick — and only
    // there.
    now = now.add(const Duration(seconds: 4));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(died, isEmpty, reason: 'no internal timer decides');
    await link.tick();
    expect(died, 'peer stale');
    expect(sent, hasLength(1), reason: 'a dead link sends nothing more');
  });
}

/// A session whose sends complete immediately and are recorded — the
/// backbone for tick-driven tests (a live inbound stream; see the
/// `const Stream.empty()` gotcha on [_GatedSession]).
final class _RecordingSession implements MeshSession {
  final sent = <Uint8List>[];
  final _inbound = StreamController<Uint8List>();
  var _closed = false;

  @override
  String get remotePeerId => 'recording';

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Future<void> send(final Uint8List payload) async {
    if (_closed) throw StateError('Session closed');
    sent.add(payload);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  /// Injects a frame as if the peer sent it.
  void receive(final Uint8List bytes) => _inbound.add(bytes);
}

/// A MeshSession whose sends park on gates — the deterministic way to
/// observe droppable coalescing. The inbound stream is LIVE (never
/// done): `const Stream.empty()` emits done ON LISTEN, which would kill
/// the link at construction — a paid-for Dart gotcha.
final class _GatedSession implements MeshSession {
  _GatedSession(this._gates, this.sent);

  final List<Completer<void>> _gates;
  final List<Uint8List> sent;
  final StreamController<Uint8List> _inbound = StreamController<Uint8List>();

  @override
  String get remotePeerId => 'gated';

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Future<void> send(final Uint8List payload) async {
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    sent.add(payload);
  }

  @override
  Future<void> close() async {}

  /// Injects a frame as if the peer sent it.
  void receive(final Uint8List bytes) => _inbound.add(bytes);
}
