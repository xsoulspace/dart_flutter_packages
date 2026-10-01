import 'dart:convert';
import 'dart:io';

import 'package:universal_lexicon/universal_lexicon.dart';

/// Stage 2 of the language-pack build (OFFLINE — no network):
///
/// ```sh
/// dart run bin/build_language_packs.dart --work /tmp/ulx_work \
///   --out assets
/// ```
///
/// Consumes the `<lang>_freq.tsv` / `<lang>_defs.tsv` /
/// `<lang>_source.json` files that `tool/fetch_language_data.dart`
/// produced and emits, per language:
/// - `<lang>.lxlex` — LexiconPack (top words + normalized frequencies)
/// - `<lang>.lxdef` — DefinitionPack (glosses for the top words)
/// - `<lang>.json`  — provenance (copied from the fetch sidecar)
void main(final List<String> args) {
  var work = '';
  var out = 'assets';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--work') work = args[i + 1];
    if (args[i] == '--out') out = args[i + 1];
  }
  if (work.isEmpty) {
    stderr.writeln('usage: dart run bin/build_language_packs.dart '
        '--work <dir> [--out assets]');
    exitCode = 64;
    return;
  }
  Directory(out).createSync(recursive: true);

  const defsPerLanguage = 3000;

  for (final entity in Directory(work).listSync()) {
    if (entity is! File || !entity.path.endsWith('_freq.tsv')) continue;
    final lang = entity.path.split('/').last.replaceAll('_freq.tsv', '');
    final counts = <String, int>{};
    for (final line in entity.readAsLinesSync()) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      counts[line.substring(0, tab)] = int.parse(line.substring(tab + 1));
    }
    final normalized = normalizeCounts(counts);
    final lexBytes = LexiconPackBuilder().build(normalized);
    File('$out/$lang.lxlex').writeAsBytesSync(lexBytes);
    stdout.writeln('$lang: ${normalized.length} words → '
        '$out/$lang.lxlex (${(lexBytes.length / 1024).toStringAsFixed(0)} KiB)');

    final defsFile = File('$work/${lang}_defs.tsv');
    if (!defsFile.existsSync()) continue;
    final byCount = counts.entries.toList()
      ..sort((final a, final b) => b.value.compareTo(a.value));
    final rank = <String, int>{};
    for (var i = 0; i < byCount.length; i++) {
      rank[byCount[i].key] = i;
    }
    final defs = <DefinitionEntry>[];
    for (final line in defsFile.readAsLinesSync()) {
      final fields = line.split('\t');
      if (fields.length < 3) continue;
      final word = fields[0];
      // Keep definitions only for words the lexicon actually carries,
      // capped at the top slice.
      final wordRank = rank[word] ?? 1 << 30;
      if (!normalized.containsKey(word) || wordRank >= defsPerLanguage) {
        continue;
      }
      defs.add(
        DefinitionEntry(
          word: word,
          partOfSpeech: fields[1].isEmpty ? null : fields[1],
          definition: fields.sublist(2).join('\t'),
        ),
      );
    }
    if (defs.isEmpty) {
      stderr.writeln('$lang: no definitions — .lxdef skipped');
      continue;
    }
    final defBytes = DefinitionPackBuilder().build(defs);
    File('$out/$lang.lxdef').writeAsBytesSync(defBytes);
    stdout.writeln('$lang: ${defs.length} senses → '
        '$out/$lang.lxdef (${(defBytes.length / 1024).toStringAsFixed(0)} KiB)');

    final source = File('$work/${lang}_source.json');
    if (source.existsSync()) {
      File('$out/$lang.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(
          <String, dynamic>{
            ...jsonDecode(source.readAsStringSync()) as Map<String, dynamic>,
            'built': DateTime.now().toUtc().toIso8601String(),
            'words': normalized.length,
            'definitions': defs.length,
          },
        ),
      );
    }
  }
}
