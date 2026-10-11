import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// Byte-level wire goldens for the anti-entropy session codec — the SAME
/// fixtures and pinned bytes as `universal_storage_mesh`'s
/// `mesh_sync_protocol_golden_test.dart`.
///
/// WHY: the codec moved verbatim out of the mesh package so mesh and ecsly
/// world sync share one protocol implementation. Two golden suites (one per
/// consumer-facing home) prove the move changed no bytes: if either copy of
/// the fixtures ever disagrees, a parent is drifting from the shared wire.
void main() {
  const peerAlphaVv = {
    'alice': Hlc(1700000000000, 3, 'alice'),
    'bob': Hlc(1700000000005, 1, 'bob'),
  };

  Map<String, Object?> helloFrame() =>
      MeshSyncProtocol.hello(peerId: 'peer-alpha', displayName: 'Alpha Device');

  Map<String, Object?> subFrame() => MeshSyncProtocol.sub(
    selection: const InterestSelection(
      docIds: {'docs/b'},
      prefixes: {'sectors/dungeon/'},
    ),
    priority: {'docs/b': 2, 'docs/a': 1},
    budget: 64,
  );

  Map<String, Object?> vvFrame() =>
      MeshSyncProtocol.vv({'docs/a': VersionVector(Map.of(peerAlphaVv))});

  Map<String, Object?> deltaFrame() => MeshSyncProtocol.delta(
    ops: [
      OpRecord(
        docId: 'docs/a',
        hlc: peerAlphaVv['alice']!,
        payload: const {'k': 'node/a/title', 'v': 'hello'},
      ),
    ],
    states: [
      Snapshot(
        docId: 'docs/a',
        baseVv: VersionVector({'alice': peerAlphaVv['alice']!}),
        state: const {'node/a/title': 'hello'},
        createdAt: peerAlphaVv['alice']!,
      ),
    ],
  );

  // Captured byte-for-byte from the pre-move mesh implementation.
  const goldenHello =
      '{"v":2,"type":"hello","peer_id":"peer-alpha",'
      '"display_name":"Alpha Device"}';
  const goldenSub =
      '{"v":1,"type":"sub","policy":{"all":false,"docs":["docs/b"],'
      '"prefixes":["sectors/dungeon/"]},"priority":{"docs/b":2,"docs/a":1},'
      '"budget":64}';
  const goldenVv =
      '{"type":"vv","docs":{"docs/a":{"alice":{"w":1700000000000,"c":3,'
      '"a":"alice"},"bob":{"w":1700000000005,"c":1,"a":"bob"}}}}';
  const goldenDelta =
      '{"type":"delta","ops":[{"doc_id":"docs/a","hlc":{"w":1700000000000,'
      '"c":3,"a":"alice"},"payload":{"k":"node/a/title","v":"hello"}}],'
      '"states":[{"doc_id":"docs/a","base_vv":{"alice":{"w":1700000000000,'
      '"c":3,"a":"alice"}},"state":{"node/a/title":"hello"},'
      '"created_at":{"w":1700000000000,"c":3,"a":"alice"}}]}';
  const goldenUnicodeHello =
      '{"v":2,"type":"hello","peer_id":"peer-beta",'
      '"display_name":"Zürich Gerät"}';

  void expectGoldenBytes(
    final String golden,
    final Map<String, Object?> frame,
  ) {
    final bytes = MeshSyncProtocol.encode(frame);
    expect(utf8.decode(bytes), golden);
    expect(bytes, Uint8List.fromList(utf8.encode(golden)));
  }

  group('exact wire bytes (mesh parity)', () {
    test('hello(v:2) encodes the pinned bytes', () {
      expectGoldenBytes(goldenHello, helloFrame());
    });

    test('sub(v:1) encodes the pinned bytes', () {
      expectGoldenBytes(goldenSub, subFrame());
    });

    test('vv encodes the pinned bytes', () {
      expectGoldenBytes(goldenVv, vvFrame());
    });

    test('delta encodes the pinned bytes', () {
      expectGoldenBytes(goldenDelta, deltaFrame());
    });

    test('non-ASCII display names encode as raw UTF-8, not escapes', () {
      expectGoldenBytes(
        goldenUnicodeHello,
        MeshSyncProtocol.hello(
          peerId: 'peer-beta',
          displayName: 'Zürich Gerät',
        ),
      );
    });
  });

  group('roundtrip decode equality', () {
    test('hello decodes back to the golden map', () {
      final decoded = MeshSyncProtocol.decode(
        MeshSyncProtocol.encode(helloFrame()),
      );
      expect(decoded, jsonDecode(goldenHello));
    });

    test('sub roundtrips through parseSub to the same bytes', () {
      final parsed = MeshSyncProtocol.parseSub(jsonDecode(goldenSub));
      final reEncoded = MeshSyncProtocol.encode(
        MeshSyncProtocol.sub(
          selection: parsed.selection,
          priority: parsed.priority,
          budget: parsed.budget,
        ),
      );
      expect(utf8.decode(reEncoded), goldenSub);
    });

    test('vv roundtrips through parseVv to the same bytes', () {
      final parsed = MeshSyncProtocol.parseVv(jsonDecode(goldenVv));
      final reEncoded = MeshSyncProtocol.encode(MeshSyncProtocol.vv(parsed));
      expect(utf8.decode(reEncoded), goldenVv);
    });

    test('delta roundtrips through parseDelta to the same bytes', () {
      final parsed = MeshSyncProtocol.parseDelta(jsonDecode(goldenDelta));
      final reEncoded = MeshSyncProtocol.encode(
        MeshSyncProtocol.delta(ops: parsed.ops, states: parsed.states),
      );
      expect(utf8.decode(reEncoded), goldenDelta);
    });
  });

  group('rejection and classifier contract', () {
    test(
      'unknown types and versions decode unchanged; malformed frames reject',
      () {
        const unknown = '{"type":"gossip","x":1}';
        expect(MeshSyncProtocol.decode(utf8.encode(unknown)), {
          'type': 'gossip',
          'x': 1,
        });
        const futureVersion =
            '{"v":99,"type":"hello","peer_id":"p","display_name":"d"}';
        expect(MeshSyncProtocol.decode(utf8.encode(futureVersion))['v'], 99);
        expect(
          () => MeshSyncProtocol.decode(utf8.encode('[1,2,3]')),
          throwsA(isA<TypeError>()),
        );
        expect(
          () => MeshSyncProtocol.decode(utf8.encode('{bad')),
          throwsA(isA<FormatException>()),
        );
        expect(() => MeshSyncProtocol.parseVv(null), throwsA(isA<Error>()));
      },
    );

    test(
      'plane classifier: sync frames true; app frames and garbage false',
      () {
        expect(
          looksLikeWorldSyncFrame(MeshSyncProtocol.encode(helloFrame())),
          isTrue,
        );
        expect(
          looksLikeWorldSyncFrame(MeshSyncProtocol.encode(deltaFrame())),
          isTrue,
        );
        expect(looksLikeWorldSyncFrame(utf8.encode('{"op":{}}')), isFalse);
        expect(looksLikeWorldSyncFrame(utf8.encode('[1,2,3]')), isFalse);
        expect(
          looksLikeWorldSyncFrame(Uint8List.fromList([0x00, 0xff, 0x10])),
          isFalse,
        );
        expect(
          meshFrameTypeIs(utf8.encode('{"type":"chunk-req"}'), const {
            'chunk-req',
          }),
          isTrue,
        );
      },
    );
  });
}
