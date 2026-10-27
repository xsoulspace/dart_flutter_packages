import 'dart:io';

import 'package:archive/archive.dart' as archive;
import 'package:test/test.dart';
import 'package:universal_lexicon/universal_lexicon.dart';

void main() {
  const codec = ZLibBlockCodec();
  // Word-list-shaped text (repetitive, like a real pack block).
  final payload = <int>[
    for (var i = 0; i < 512; i++)
      ...('word${i % 97}\tgloss number $i here\n'.codeUnits),
  ];

  test('roundtrip through the default codec', () {
    expect(codec.decode(codec.encode(payload)), payload);
  });

  test('cross-compat: native zlib bytes decode (packs built on native '
      'must read on web)', () {
    final nativeEncoded = ZLibCodec().encode(payload);
    expect(codec.decode(nativeEncoded), payload);
  });

  test('cross-compat: our bytes decode with native zlib', () {
    expect(ZLibCodec().decode(codec.encode(payload)), payload);
  });

  test('the WEB code path (pure-Dart Inflate) reads our blocks', () {
    // ZLibDecoderWeb is exactly what archive's platform dispatch picks
    // on the browser — exercising it here pins the web behavior on the
    // VM.
    expect(
      const archive.ZLibDecoderWeb().decodeBytes(codec.encode(payload)),
      payload,
    );
    expect(
      codec.decode(const archive.ZLibEncoderWeb().encodeBytes(payload)),
      payload,
    );
  });
}
