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
}
