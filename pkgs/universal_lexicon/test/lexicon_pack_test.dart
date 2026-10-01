import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_lexicon/universal_lexicon.dart';

void main() {
  test('roundtrip: words + frequencies survive the bytes', () {
    final bytes = LexiconPackBuilder().build(
      const {'hello': 0.7, 'help': 0.75, 'here': 0.8},
    );
    final pack = LexiconPack(bytes);
    expect(pack.wordCount, 3);
    expect(pack.frequencies['hello'], closeTo(0.7, 0.001));
    expect(pack.frequencies['help'], closeTo(0.75, 0.001));
    expect(pack.frequencies['here'], closeTo(0.8, 0.001));
  });

  test('toLexicon answers ranked prefix queries', () {
    final bytes = LexiconPackBuilder().build(
      const {'hello': 0.7, 'help': 0.75, 'here': 0.8},
    );
    final lexicon = LexiconPack(bytes).toLexicon();
    expect(lexicon.prefixCandidates('he').map((final m) => m.word), [
      'here',
      'help',
      'hello',
    ]);
  });

  test('quantization is fine enough to preserve ranking', () {
    final bytes = LexiconPackBuilder().build(
      const {'a': 0.1234, 'b': 0.1236, 'c': 0.9},
    );
    final frequencies = LexiconPack(bytes).frequencies;
    expect(frequencies['c']! > frequencies['b']!, isTrue);
    expect(frequencies['b']! > frequencies['a']!, isTrue);
  });

  test('rejects foreign bytes and empty input', () {
    expect(
      () => LexiconPack(Uint8List.fromList([1, 2, 3])),
      throwsArgumentError,
    );
    expect(() => LexiconPackBuilder().build(const {}), throwsArgumentError);
  });
}
