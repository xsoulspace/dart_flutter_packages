import 'package:universal_io/io.dart';

import 'package:universal_lexicon/universal_lexicon.dart';

/// Reads a DefinitionPack and prints lookups — the end-to-end smoke:
///
/// ```sh
/// dart run example/definition_pack_smoke.dart definitions.lxdef panda zzz
/// ```
void main(final List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run example/definition_pack_smoke.dart '
        '<pack.lxdef> [words...]');
    exitCode = 64;
    return;
  }
  final bytes = File(args.first).readAsBytesSync();
  final pack = DefinitionPack(bytes);
  stdout.writeln(
    'entries: ${pack.entryCount}, blocks: ${pack.blockCount}, '
    'file: ${bytes.length} B, resident cache: ≤${pack.maxCachedBlocks} '
    'blocks',
  );
  for (final word in args.skip(1)) {
    final definition = pack.definition(word);
    stdout.writeln(
      definition == null ? '$word → (unknown)' : '$word → $definition',
    );
  }
}
