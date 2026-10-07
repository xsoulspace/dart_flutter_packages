import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  group('ZoneCatalog', () {
    test('json round-trip', () {
      const catalog = ZoneCatalog(
        zoneId: 'dungeon',
        title: 'The Dungeon',
        entries: [
          ZoneMemberEntry(docId: 'docs/chat-1', title: 'Party chat', kind: 'chat'),
          ZoneMemberEntry(
            docId: 'assets/dragon.png',
            kind: 'blob',
            meta: {'size': 2048},
          ),
        ],
      );
      final restored = ZoneCatalog.fromJson(catalog.toJson());
      expect(restored.zoneId, 'dungeon');
      expect(restored.title, 'The Dungeon');
      expect(restored.memberDocIds(), {'docs/chat-1', 'assets/dragon.png'});
      expect(restored.entries[1].meta, {'size': 2048});
    });

    test('memberDocIds over an empty catalog', () {
      const catalog = ZoneCatalog(zoneId: 'empty');
      expect(catalog.memberDocIds(), isEmpty);
    });
  });

  group('ZoneCatalogCodec', () {
    test('encode -> applyLocal -> decode round-trips through a real doc', () {
      final doc = ConvergenceDoc(docId: 'zones/dungeon', actorId: 'tester');
      doc.applyLocal(
        ZoneCatalogCodec.encode(
          const ZoneCatalog(
            zoneId: 'dungeon',
            entries: [ZoneMemberEntry(docId: 'docs/a', title: 'A')],
          ),
        ),
        DateTime.now(),
      );
      final catalog = ZoneCatalogCodec.decode(doc);
      expect(catalog, isNotNull);
      expect(catalog!.zoneId, 'dungeon');
      expect(catalog.memberDocIds(), {'docs/a'});
    });

    test('decode returns null for docs without a census', () {
      final doc = ConvergenceDoc(docId: 'docs/plain', actorId: 'tester');
      doc.applyLocal({'k': 'content', 'v': 'not a catalog'}, DateTime.now());
      expect(ZoneCatalogCodec.decode(doc), isNull);
    });

    test('decode returns null for malformed census payloads', () {
      final doc = ConvergenceDoc(docId: 'zones/bad', actorId: 'tester');
      doc.applyLocal({
        'k': ZoneCatalogCodec.registerKey,
        'v': {'zoneId': 42},
      }, DateTime.now());
      expect(ZoneCatalogCodec.decode(doc), isNull);
    });
  });
}
