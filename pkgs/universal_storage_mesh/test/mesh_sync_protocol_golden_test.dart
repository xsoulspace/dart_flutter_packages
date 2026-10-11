import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

/// Byte-level wire goldens for the mesh anti-entropy protocol (ADR 0010 §4,
/// ADR 0048 §2).
///
/// WHY: the protocol codec is about to move into the shared anti-entropy
/// session core while the mesh wire must stay byte-identical — peers across
/// versions only interoperate if every envelope keeps its exact shape. These
/// goldens pin the CURRENT implementation's bytes as UTF-8 literals (captured
/// from the pre-move codec); they must pass unchanged after any refactor of
/// the codec's home.
///
/// Rejection contract pinned here (current behavior): the codec layer decodes
/// any valid JSON map — unknown `type` values and unknown `v` versions are
/// carried through unchanged, and skipping/rejecting them is the session
/// loop's decision, not the codec's. Only malformed frames (non-map JSON,
/// broken JSON, null bodies at the typed parsers) are rejected at this layer.
void main() {
  // Fixed fixtures — never derived from clocks or randomness, so the bytes
  // below are stable forever.
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

  // Captured byte-for-byte from the current implementation. The final
  // `Zürich Gerät` frame additionally pins UTF-8 (non-ASCII) encoding.
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

  /// The exact-bytes assertion: the encoded frame must equal the golden
  /// UTF-8 bytes — not a semantically equal JSON re-serialization.
  void expectGoldenBytes(
    final String golden,
    final Map<String, Object?> frame,
  ) {
    final bytes = MeshSyncProtocol.encode(frame);
    expect(utf8.decode(bytes), golden);
    expect(bytes, Uint8List.fromList(utf8.encode(golden)));
  }

  group('exact wire bytes', () {
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

  group('codec-level rejection contract', () {
    test('unknown frame types decode unchanged (session decides skipping)', () {
      const frame = '{"type":"gossip","x":1}';
      expect(MeshSyncProtocol.decode(utf8.encode(frame)), {
        'type': 'gossip',
        'x': 1,
      });
    });

    test(
      'unsupported hello versions decode unchanged (session gates versions)',
      () {
        const frame =
            '{"v":99,"type":"hello","peer_id":"p","display_name":"d"}';
        final decoded = MeshSyncProtocol.decode(utf8.encode(frame));
        expect(decoded['v'], 99);
      },
    );

    test('non-map JSON (array) is rejected by decode', () {
      const frame = '[1,2,3]';
      expect(
        () => MeshSyncProtocol.decode(utf8.encode(frame)),
        throwsA(isA<TypeError>()),
      );
    });

    test('broken JSON bytes are rejected by decode', () {
      const frame = '{"type": "hello",,}';
      expect(
        () => MeshSyncProtocol.decode(utf8.encode(frame)),
        throwsA(isA<FormatException>()),
      );
    });

    test('typed parsers reject null bodies', () {
      expect(() => MeshSyncProtocol.parseSub(null), throwsA(isA<Error>()));
      expect(() => MeshSyncProtocol.parseVv(null), throwsA(isA<Error>()));
      expect(() => MeshSyncProtocol.parseDelta(null), throwsA(isA<Error>()));
    });
  });

  group('looksLikeWorldSyncFrame classifier', () {
    test('every sync envelope type classifies as world-sync', () {
      for (final frame in [helloFrame(), subFrame(), vvFrame(), deltaFrame()]) {
        expect(
          looksLikeWorldSyncFrame(MeshSyncProtocol.encode(frame)),
          isTrue,
          reason: 'frame type ${frame['type']} must route to the sync plane',
        );
      }
    });

    test('unknown types do not route to the sync plane', () {
      const frame = '{"type":"gossip","x":1}';
      expect(looksLikeWorldSyncFrame(utf8.encode(frame)), isFalse);
    });

    test('presence-style frames (op-shaped, no type) do not route to sync', () {
      const frame = '{"op":{"peer":"peer-alpha","state":"live"}}';
      expect(looksLikeWorldSyncFrame(utf8.encode(frame)), isFalse);
    });

    test('JSON arrays do not route to the sync plane', () {
      const frame = '[1,2,3]';
      expect(looksLikeWorldSyncFrame(utf8.encode(frame)), isFalse);
    });

    test('non-JSON bytes do not route to the sync plane', () {
      final frame = Uint8List.fromList([0x00, 0xff, 0x10, 0x80]);
      expect(looksLikeWorldSyncFrame(frame), isFalse);
    });

    test('empty frames do not route to the sync plane', () {
      expect(looksLikeWorldSyncFrame(Uint8List(0)), isFalse);
    });

    test('meshFrameTypeIs serves other planes (blob lane example)', () {
      const chunkReq = '{"type":"chunk-req","id":"c1"}';
      const hello = '{"v":2,"type":"hello","peer_id":"p","display_name":"d"}';
      expect(
        meshFrameTypeIs(utf8.encode(chunkReq), const {'chunk-req', 'chunk'}),
        isTrue,
      );
      expect(
        meshFrameTypeIs(utf8.encode(hello), const {'chunk-req', 'chunk'}),
        isFalse,
      );
    });
  });
}
