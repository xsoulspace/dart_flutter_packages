import 'dart:convert';
import 'package:universal_io/io.dart';

import 'package:universal_lexicon/universal_lexicon.dart';

/// Builds a DefinitionPack from a UTF-8 TSV file: one sense per line,
/// `word<TAB>partOfSpeech<TAB>definition`; `#` lines are comments.
///
/// ```sh
/// dart run universal_lexicon:build_definition_pack \
///   definitions.tsv definitions.lxdef [--per-block 64]
/// ```
///
/// Data sources and license notes live in the package README; the
/// provenance (source, extraction date, commit) belongs in a
/// sidecar `*.json` next to the pack — the pack itself stays data-only.
void main(final List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run universal_lexicon:build_definition_pack '
      '<input.tsv> <output.lxdef> [--per-block N]',
    );
    exitCode = 64;
    return;
  }
  final input = File(args[0]);
  final output = File(args[1]);
  var perBlock = definitionPackEntriesPerBlock;
  for (var i = 2; i < args.length - 1; i++) {
    if (args[i] == '--per-block') {
      perBlock = int.tryParse(args[i + 1]) ?? perBlock;
    }
  }

  final entries = <DefinitionEntry>[];
  var lineNumber = 0;
  for (final rawLine in input.readAsLinesSync()) {
    lineNumber++;
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final fields = line.split('\t');
    if (fields.length < 3) {
      stderr.writeln('line $lineNumber: expected 3 TAB fields, '
          'got ${fields.length}');
      exitCode = 65;
      return;
    }
    entries.add(
      DefinitionEntry(
        word: fields[0].trim().toLowerCase(),
        partOfSpeech: fields[1].trim().isEmpty ? null : fields[1].trim(),
        definition: fields.sublist(2).join('\t').trim(),
      ),
    );
  }

  final bytes = DefinitionPackBuilder(entriesPerBlock: perBlock).build(
    entries,
  );
  output.writeAsBytesSync(bytes);
  stdout.writeln(
    '${entries.length} entries → ${output.path} '
    '(${(bytes.length / 1024).toStringAsFixed(1)} KiB)',
  );
  const provenance = JsonEncoder.withIndent('  ');
  stderr
    ..write(
      provenance.convert(<String, Object?>{
        'format': 'universal_lexicon DefinitionPack v1',
        'entries': entries.length,
        'note': 'record the source, license, and extraction date here',
      }),
    )
    ..writeln();
}
