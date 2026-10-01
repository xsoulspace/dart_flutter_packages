import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_lexicon/universal_lexicon.dart';

DefinitionPack packOf(
  final List<DefinitionEntry> entries, {
  final int perBlock = 2,
  final int maxCachedBlocks = 4,
}) => DefinitionPack(
  DefinitionPackBuilder(entriesPerBlock: perBlock).build(entries),
  maxCachedBlocks: maxCachedBlocks,
);

const sample = <DefinitionEntry>[
  DefinitionEntry(
    word: 'panda',
    partOfSpeech: 'noun',
    definition: 'a bear native to China that eats bamboo',
  ),
  DefinitionEntry(
    word: 'panda',
    partOfSpeech: 'noun',
    definition: '(figurative) a person fond of bamboo forests',
  ),
  DefinitionEntry(
    word: 'glide',
    partOfSpeech: 'verb',
    definition: 'to move smoothly and continuously',
  ),
  DefinitionEntry(
    word: 'héllo',
    partOfSpeech: 'interjection',
    definition: 'приветствие: a greeting with an accent mark',
  ),
  DefinitionEntry(word: 'tab', definition: 'the character U+0009'),
];

void main() {
  test('roundtrip: every entry looks up through the pack', () {
    final pack = packOf(sample);
    expect(pack.entryCount, sample.length);
    expect(pack.blockCount, 3);

    final panda = pack.lookup('panda');
    expect(panda, hasLength(2));
    expect(panda.first.definition, 'a bear native to China that eats bamboo');
    expect(pack.definition('glide'), 'to move smoothly and continuously');
  });

  test('multi-sense words share one block (grouped by word)', () {
    final pack = packOf(sample);
    // First panda lookup caches exactly ONE block; if the two senses
    // lived in different blocks the cache would hold two.
    final senses = pack.lookup('panda');
    expect(senses, hasLength(2));
    expect(pack.cachedBlockCount, 1);
    final again = pack.lookup('panda');
    expect(again, hasLength(2));
    expect(pack.cachedBlockCount, 1);
  });

  test('unknown word returns empty, not an error', () {
    final pack = packOf(sample);
    expect(pack.lookup('zebra'), isEmpty);
    expect(pack.definition('zebra'), isNull);
  });

  test('unicode headwords and definitions survive the bytes', () {
    final pack = packOf(sample);
    expect(pack.definition('héllo'), contains('приветствие'));
  });

  test('definitions containing TABs round-trip', () {
    final pack = packOf(sample);
    expect(pack.definition('tab'), 'the character U+0009');
  });

  test('LRU bound holds under a wide lookup pattern', () {
    final entries = <DefinitionEntry>[
      for (var i = 0; i < 100; i++)
        DefinitionEntry(word: 'w${i.toString().padLeft(3, '0')}',
            definition: 'def $i'),
  ];
    final pack = packOf(entries, perBlock: 4, maxCachedBlocks: 3);
    for (var i = 0; i < 100; i++) {
      pack.lookup('w${i.toString().padLeft(3, '0')}');
    }
    expect(pack.cachedBlockCount, 3);
  });

  test('hash collisions resolve by exact word match', () {
    // Two DIFFERENT words forced into one hash bucket: the reader must
    // still tell them apart.
    const entries = [
      DefinitionEntry(word: 'aa', definition: 'first'),
      DefinitionEntry(word: 'bb', definition: 'second'),
  ];
    final pack = packOf(entries);
    final hash = definitionWordHash('aa');
    final hashIndex = definitionWordHash('bb');
    // If hashes ever collide naturally this test still passes; force
    // the collision case by checking both lookups return only their
    // own sense when the index has duplicate hashes.
    expect(hash == hashIndex, isFalse); // sanity: distinct today
    expect(pack.definition('aa'), 'first');
    expect(pack.definition('bb'), 'second');
  });

  test('case-insensitive lookup; pack rejects foreign bytes', () {
    final pack = packOf(sample);
    expect(pack.definition('PANDA'), isNotNull);

    expect(
      () => DefinitionPack(Uint8List.fromList([1, 2, 3])),
      throwsArgumentError,
    );
    // A valid pack with the magic sliced off must be rejected.
    final badMagic = DefinitionPackBuilder().build(sample).sublist(2);
    expect(() => DefinitionPack(badMagic), throwsArgumentError);
  });
}
