// The multi-sender host: authority arbitration, release safety, and the
// adoption proof — a VOSGES-SHAPED vocabulary (droppable pointerMove
// frames with x/y/confidence, reliable pinch edges) driven through the
// library primitives over a fake hub. An app like vosges brings its
// schema and (only for richer fusion) a custom arbiter; the session
// plumbing, heartbeats, dedupe, and arbitration shell are the library's.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_realtime/universal_storage_realtime.dart';

Uint8List _frame(final RealtimeEnvelope envelope) => envelope.encode();

Future<void> _pump() => pumpEventQueue();

void main() {
  test('vosges-shaped adoption: claim, fusion visibility, release safety',
      () async {
    final hub = FakeMeshHub();
    final routed = <({String sender, String type, bool authoritative})>[];
    final releases = <String>[];
    final senderChanges = <String?>[];
    final host = RealtimeHost(
      claimedPlane: hub,
      selfId: 'desktop',
      onEvent: (final event, {required final bool authoritative}) => routed.add(
        (
          sender: event.senderPeerId,
          type: event.type,
          authoritative: authoritative,
        ),
      ),
      onReleaseAll: releases.add,
      onSenderChanged: (final sender, final _) => senderChanges.add(sender),
    );
    host.start();

    // Phone A joins and speaks the gesture vocabulary.
    final a = hub.openSession('phone-a');
    a.receive(_frame(RealtimeEnvelope(
      type: 'pinchStart',
      seq: 1,
      reliable: true,
      issuedAtMs: 0,
      payload: {'confidence': 0.9},
    )));
    a.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 1,
      reliable: false,
      issuedAtMs: 0,
      payload: {'x': 0.5, 'y': 0.5, 'confidence': 0.9},
    )));
    a.receive(_frame(RealtimeEnvelope(
      type: 'pinchEnd',
      seq: 2,
      reliable: true,
      issuedAtMs: 0,
    )));
    await _pump();

    expect(host.activeSender, 'phone-a', reason: 'first routable event claims');
    expect(
      routed.map((final r) => r.type).toList(),
      ['pinchStart', 'pointerMove', 'pinchEnd'],
      reason: 'reliable AND droppable app events both surface',
    );
    expect(routed.every((final r) => r.authoritative), isTrue);
    expect(senderChanges, ['phone-a']);

    // Phone B joins while A is fresh: B's events surface as
    // NON-authoritative (fusion policies consume them directly), B never
    // steals the claim.
    final b = hub.openSession('phone-b');
    routed.clear();
    b.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 1,
      reliable: false,
      issuedAtMs: 0,
      payload: {'x': 0.9, 'y': 0.1, 'confidence': 0.8},
    )));
    await _pump();
    expect(host.activeSender, 'phone-a');
    expect(routed.single.sender, 'phone-b');
    expect(routed.single.authoritative, isFalse);

    // The active sender releases: held input is released BEFORE the
    // claim clears (the safety law), and B may then claim.
    routed.clear();
    senderChanges.clear();
    a.receive(_frame(RealtimeEnvelope(
      type: 'release-all',
      seq: 3,
      reliable: true,
      issuedAtMs: 0,
    )));
    await _pump();
    expect(releases.single, contains('phone-a released'));
    expect(host.activeSender, isNull);
    expect(senderChanges.single, isNull);

    b.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 2,
      reliable: false,
      issuedAtMs: 0,
      payload: {'x': 0.2, 'y': 0.8, 'confidence': 0.7},
    )));
    await _pump();
    expect(host.activeSender, 'phone-b');

    // Losing the active sender's session releases what it held.
    routed.clear();
    releases.clear();
    senderChanges.clear();
    b.closeLocally();
    await _pump();
    expect(host.activeSender, isNull);
    expect(releases.single, contains('phone-b lost'));
    expect(senderChanges.single, isNull);

    // Heartbeats the host sent reached the sender (liveness is
    // bidirectional) and were never surfaced as app events.
    expect(
      a.sent.every(
        (final bytes) =>
            RealtimeEnvelope.tryDecode(bytes)!.type == 'heartbeat',
      ),
      isTrue,
    );
    expect(routed, isEmpty, reason: 'control frames never route');

    await host.close();
  });

  test('a custom arbiter rewires authority without touching the shell',
      () async {
    final hub = FakeMeshHub();
    // Round-robin-flavored policy: every event hands authority to the
    // candidate (nobody keeps the claim — absurd, but proves the seam).
    final claims = <String?>[];
    final host = RealtimeHost(
      claimedPlane: hub,
      selfId: 'desktop',
      arbiter: const _CandidateAlwaysArbiter(),
      onEvent: (final event, {required final bool authoritative}) {},
      onSenderChanged: (final sender, final _) => claims.add(sender),
    );
    host.start();

    final a = hub.openSession('phone-a');
    a.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 1,
      reliable: false,
      issuedAtMs: 0,
    )));
    await _pump();
    expect(host.activeSender, 'phone-a');

    final b = hub.openSession('phone-b');
    b.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 1,
      reliable: false,
      issuedAtMs: 0,
    )));
    await _pump();
    expect(host.activeSender, 'phone-b', reason: 'the policy decides');
    expect(claims, ['phone-a', 'phone-b']);

    await host.close();
  });

  test('the adoption gate rejects untrusted sessions before any link',
      () async {
    final hub = FakeMeshHub();
    final host = RealtimeHost(
      claimedPlane: hub,
      selfId: 'desktop',
      adoptSession: (final session) => session.remotePeerId == 'phone-a',
      onEvent: (final event, {required final bool authoritative}) {},
    );
    host.start();

    final a = hub.openSession('phone-a');
    final stranger = hub.openSession('stranger');
    await _pump();
    a.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 1,
      reliable: false,
      issuedAtMs: 0,
    )));
    await _pump();

    expect(host.senders.single.peerId, 'phone-a');
    expect(
      stranger.closedByPeer,
      isTrue,
      reason: 'a rejected session is closed untouched — the auth seam',
    );
    await host.close();
  });

  test('tick-driven host pulses links: nothing moves until tick()', () async {
    final hub = FakeMeshHub();
    var now = DateTime.utc(2026, 9, 27, 12);
    final releases = <String>[];
    final host = RealtimeHost(
      claimedPlane: hub,
      selfId: 'desktop',
      tickDriven: true,
      heartbeatInterval: const Duration(seconds: 1),
      staleAfter: const Duration(seconds: 3),
      clock: () => now,
      onEvent: (final event, {required final bool authoritative}) {},
      onReleaseAll: releases.add,
    );
    host.start();

    final a = hub.openSession('phone-a');
    a.receive(_frame(RealtimeEnvelope(
      type: 'pointerMove',
      seq: 1,
      reliable: false,
      issuedAtMs: 0,
    )));
    await _pump();
    expect(host.activeSender, 'phone-a');

    // Real time passing past the stale window decides nothing.
    now = now.add(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(host.activeSender, 'phone-a', reason: 'no internal timer decides');

    // The consumer's own watchdog pulse drops the silent sender.
    await host.tick();
    await _pump();
    expect(host.activeSender, isNull);
    expect(releases.single, contains('phone-a lost'));
    expect(a.closedByPeer, isTrue, reason: 'the dead link closed its session');
    await host.close();
  });
}

final class _CandidateAlwaysArbiter implements RealtimeArbiter {
  const _CandidateAlwaysArbiter();

  @override
  String? arbitrate({
    required final String? active,
    required final String candidate,
    required final DateTime? activeLastEventAt,
    required final DateTime now,
  }) => candidate;
}
