import 'package:test/test.dart';

import 'package:dart_changesets/src/changeset.dart';

void main() {
  group('Changeset.parse', () {
    test('parses frontmatter and body', () {
      final changeset = Changeset.parse(
        '.changesets/a.md',
        "---\n'pkg_a': minor\n---\n\nAdd the thing.\n",
      );
      expect(changeset.bumps, {'pkg_a': BumpType.minor});
      expect(changeset.body, 'Add the thing.');
    });

    test('supports multiple packages in one file', () {
      final changeset = Changeset.parse(
        '.changesets/b.md',
        "---\n'pkg_a': patch\n'pkg_b': major\n---\n\nBoth.\n",
      );
      expect(changeset.bumps['pkg_a'], BumpType.patch);
      expect(changeset.bumps['pkg_b'], BumpType.major);
    });

    test('rejects unknown bump type', () {
      expect(
        () => Changeset.parse('.changesets/c.md', "---\n'pkg': banana\n---\n"),
        throwsA(isA<ChangesetParseException>()),
      );
    });

    test('rejects missing frontmatter', () {
      expect(
        () => Changeset.parse('.changesets/d.md', 'just prose'),
        throwsA(isA<ChangesetParseException>()),
      );
    });

    test('rejects unclosed frontmatter', () {
      expect(
        () => Changeset.parse('.changesets/e.md', "---\n'pkg': minor\n"),
        throwsA(isA<ChangesetParseException>()),
      );
    });

    test('empty body is allowed', () {
      final changeset = Changeset.parse(
        '.changesets/f.md',
        "---\n'pkg': patch\n---\n",
      );
      expect(changeset.body, isEmpty);
    });

    test('bump ranks order correctly', () {
      expect(BumpType.patch.rank, lessThan(BumpType.minor.rank));
      expect(BumpType.minor.rank, lessThan(BumpType.major.rank));
    });
  });
}
