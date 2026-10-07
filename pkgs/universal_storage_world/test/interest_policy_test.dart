import 'package:test/test.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  group('InterestSelection', () {
    test('all matches everything', () {
      const all = InterestSelection.all();
      expect(all.matchesDocId('anything/at/all'), isTrue);
      expect(all.all, isTrue);
    });

    test('none matches nothing', () {
      const none = InterestSelection.none();
      expect(none.matchesDocId('anything'), isFalse);
    });

    test('explicit ids match exactly', () {
      const selection = InterestSelection(docIds: {'docs/a', 'docs/b'});
      expect(selection.matchesDocId('docs/a'), isTrue);
      expect(selection.matchesDocId('docs/c'), isFalse);
    });

    test('prefixes match whole subtrees', () {
      const selection = InterestSelection(prefixes: {'sectors/dungeon/'});
      expect(selection.matchesDocId('sectors/dungeon/room-3'), isTrue);
      expect(selection.matchesDocId('sectors/forest/room-1'), isFalse);
    });

    test('union merges ids and prefixes and ORs the wildcard', () {
      const a = InterestSelection(docIds: {'x'}, prefixes: {'p/'});
      const b = InterestSelection(docIds: {'y'}, prefixes: {'q/'});
      final union = a.union(b);
      expect(union.matchesDocId('x'), isTrue);
      expect(union.matchesDocId('y'), isTrue);
      expect(union.matchesDocId('p/anything'), isTrue);
      expect(union.matchesDocId('q/anything'), isTrue);
      expect(union.matchesDocId('z'), isFalse);

      expect(
        a.union(const InterestSelection.all()).all,
        isTrue,
      );
    });

    test('json round-trip is canonical (sorted, auditable)', () {
      const selection = InterestSelection(docIds: {'b', 'a'}, prefixes: {'z/', 'a/'});
      final restored = InterestSelection.fromJson(selection.toJson());
      expect(restored.matchesDocId('a'), isTrue);
      expect(restored.matchesDocId('b'), isTrue);
      expect(restored.matchesDocId('a/x'), isTrue);
      expect(restored.matchesDocId('z/x'), isTrue);
      expect(restored.matchesDocId('m'), isFalse);
      expect((selection.toJson()['docs'] as List).first, 'a');
    });
  });

  group('InterestPolicy resolvers', () {
    test('AllInterest resolves to the wildcard', () {
      expect(const AllInterest().resolve().all, isTrue);
    });

    test('StaticInterestPolicy resolves to its selection', () {
      const policy = StaticInterestPolicy(InterestSelection(docIds: {'d'}));
      expect(policy.resolve().matchesDocId('d'), isTrue);
    });

    test('MemberSetInterest and MemberPrefixInterest build selections', () {
      expect(
        const MemberSetInterest({'a'}).resolve().matchesDocId('a'),
        isTrue,
      );
      expect(
        const MemberPrefixInterest({'sectors/'}).resolve().matchesDocId(
          'sectors/x',
        ),
        isTrue,
      );
    });

    test('UnionInterest composes policies', () {
      const policy = UnionInterest([
        MemberSetInterest({'open-doc'}),
        MemberPrefixInterest({'sectors/dungeon/'}),
      ]);
      final selection = policy.resolve();
      expect(selection.matchesDocId('open-doc'), isTrue);
      expect(selection.matchesDocId('sectors/dungeon/r1'), isTrue);
      expect(selection.matchesDocId('sectors/forest/r1'), isFalse);
    });
  });
}
