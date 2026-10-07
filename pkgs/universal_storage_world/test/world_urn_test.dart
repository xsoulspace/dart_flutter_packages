import 'package:test/test.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  group('WorldUrn', () {
    test('round-trips through parse and value', () {
      const raw = 'world://my-game/sectors/dungeon/room-3';
      final urn = WorldUrn.parse(raw);
      expect(urn.worldId, 'my-game');
      expect(urn.memberPath, 'sectors/dungeon/room-3');
      expect(urn.value, raw);
      expect(WorldUrn.parse(urn.value), urn);
    });

    test('json round-trip', () {
      final urn = WorldUrn.parse('world://ws/docs/chat-1');
      expect(WorldUrn.fromJson(urn.toJson()), urn);
    });

    test('child joins under the path prefix', () {
      final zone = WorldUrn.parse('world://ws/sectors/dungeon');
      expect(zone.child('room-3').value, 'world://ws/sectors/dungeon/room-3');
    });

    test('rejects malformed urns', () {
      for (final raw in <String>[
        'http://ws/docs',
        'world://',
        'world://only-world',
        'world://ws/',
        'world:///docs',
      ]) {
        expect(
          () => WorldUrn.parse(raw),
          throwsFormatException,
          reason: raw,
        );
        expect(WorldUrn.tryParse(raw), isNull, reason: raw);
      }
    });

    test('equality is structural', () {
      expect(WorldUrn.parse('world://a/b'), WorldUrn.parse('world://a/b'));
      expect(
        WorldUrn.parse('world://a/b').hashCode,
        WorldUrn.parse('world://a/b').hashCode,
      );
    });
  });

  group('PathUrnResolver', () {
    test('identity mapping preserves docId byte-for-byte', () {
      const resolver = PathUrnResolver();
      final urn = resolver.urnForDoc('docs/chat-1.json', worldId: 'ws-9');
      expect(urn.value, 'world://ws-9/docs/chat-1.json');
      expect(resolver.docIdForUrn(urn), 'docs/chat-1.json');
    });

    test('default world id when none given', () {
      const resolver = PathUrnResolver();
      expect(resolver.urnForDoc('x').value, 'world://local/x');
    });
  });
}
