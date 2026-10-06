import 'package:test/test.dart';
import 'package:universal_lexicon/universal_lexicon.dart';

void main() {
  Lexicon lexiconOf() => ListLexicon(
    words: const ['hello', 'help', 'here', 'world', 'wide', 'web'],
    frequencies: const {
      'hello': 0.7,
      'help': 0.75,
      'here': 0.8,
      'world': 0.9,
      'wide': 0.45,
      'web': 0.6,
    },
  );

  test('contains and frequencyOf are case-insensitive', () {
    final lexicon = lexiconOf();
    expect(lexicon.contains('HELLO'), isTrue);
    expect(lexicon.contains('helio'), isFalse);
    expect(lexicon.frequencyOf('World'), 0.9);
    expect(lexicon.frequencyOf('unknown'), 0.0);
  });

  test('words are lowercased and deduplicated', () {
    final lexicon = ListLexicon(words: const ['Ab', 'ab', 'CD']);
    expect(lexicon.wordCount, 2);
    expect(lexicon.contains('cd'), isTrue);
  });

  test('prefix candidates rank by frequency, length breaks ties', () {
    final matches = lexiconOf().prefixCandidates('he');
    expect(matches.map((final m) => m.word).toList(), [
      'here',
      'help',
      'hello',
    ]);
  });

  test('limit caps the results', () {
    final matches = lexiconOf().prefixCandidates('he', limit: 2);
    expect(matches, hasLength(2));
    expect(matches.first.word, 'here');
  });

  test('equal frequency falls back to shorter then lexicographic', () {
    final lexicon = ListLexicon(
      words: const ['bolt', 'bolster', 'bolero'],
      frequencies: const {'bolt': 0.5, 'bolster': 0.5, 'bolero': 0.5},
    );
    expect(lexicon.prefixCandidates('bol').map((final m) => m.word), [
      'bolt',
      'bolero',
      'bolster',
    ]);
  });

  test('unknown prefix returns empty; unknown words rank as 0', () {
    final lexicon = lexiconOf();
    expect(lexicon.prefixCandidates('zz'), isEmpty);
    expect(
      lexicon.prefixCandidates('w').map((final m) => m.word),
      containsAll(['world', 'wide', 'web']),
    );
  });

  test('missing frequency map is legal (pure word list)', () {
    final lexicon = ListLexicon(words: const ['alpha', 'also']);
    // Zero-frequency tie → shorter word first.
    expect(lexicon.prefixCandidates('al').first.word, 'also');
  });
  fuzzyPrefixTests();
}

void fuzzyPrefixTests() {
  late ListLexicon lexicon;
  setUp(() {
    lexicon = ListLexicon(
      words: const ['hello', 'help', 'held', 'here', 'name', 'same', 'go'],
      frequencies: const {
        'hello': 0.9,
        'help': 0.5,
        'held': 0.4,
        'here': 0.3,
        'name': 0.8,
        'same': 0.2,
        'go': 0.6,
      },
    );
  });

  test('fuzzy prefix: an extra letter still finds the word', () {
    final matches = lexicon.fuzzyPrefixCandidates('helo');
    expect(matches.first.word, 'hello', reason: 'frequency breaks near-ties');
    expect(matches, contains(isA<LexiconMatch>()));
  });

  test('fuzzy prefix: a missing letter still finds the word', () {
    final matches = lexicon.fuzzyPrefixCandidates('hell');
    expect(matches.map((m) => m.word), contains('hello'));
  });

  test('fuzzy prefix: exact prefixes rank first (distance order)', () {
    final matches = lexicon.fuzzyPrefixCandidates('hel', limit: 5);
    expect(matches.first.word, 'hello',
        reason: 'distance-0 head AND the highest frequency');
    expect(
      matches.map((m) => m.word).take(3),
      containsAllInOrder(['hello', 'help']),
      reason: 'distance first, then frequency',
    );
    for (final match in matches) {
      expect(match.word, startsWith('h'));
    }
  });

  test('fuzzy prefix: the distance cap refuses strangers', () {
    expect(
      lexicon.fuzzyPrefixCandidates('xyz'),
      isEmpty,
    );
  });

  test('fuzzy prefix: a short probe matches longer heads', () {
    final matches = lexicon.fuzzyPrefixCandidates('na');
    expect(matches.map((m) => m.word), contains('name'));
  });
}
