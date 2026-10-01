import 'dart:convert';
import 'dart:io';

/// Stage 1 of the language-pack build (NEEDS NETWORK — a VM-only build
/// tool, not library code):
///
/// ```sh
/// curl -o sources/wordnet.zip \
///   https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/wordnet.zip
/// unzip -o sources/wordnet.zip -d sources/wordnet
/// # plus <lang>_50k.txt from hermitdave/FrequencyWords (en ru zh ja es pt it)
/// dart run tool/fetch_language_data.dart --sources sources --work work
/// ```
///
/// Produces, per language, in the work dir:
/// - `<lang>_freq.tsv` — `word<TAB>count` (top [topWords] rows)
/// - `<lang>_defs.tsv` — `word<TAB>pos<TAB>gloss`
/// - `<lang>_source.json` — provenance sidecar
///
/// Sources: OpenSubtitles frequency lists (hermitdave/FrequencyWords,
/// CC-BY-SA), WordNet 3.1 glosses (en, permissive license), English
/// Wiktionary wikitext glosses (all other languages, CC-BY-SA —
/// English glosses in v1; native Wiktionaries are the upgrade path).
Future<void> main(final List<String> args) async {
  var sources = '';
  var work = '';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--sources') sources = args[i + 1];
    if (args[i] == '--work') work = args[i + 1];
  }
  if (sources.isEmpty || work.isEmpty) {
    stderr.writeln('usage: dart run tool/fetch_language_data.dart '
        '--sources <dir> --work <dir>');
    exitCode = 64;
    return;
  }
  Directory(work).createSync(recursive: true);

  const languages = <String, ({String freqFile, String? section})>{
    'en': (freqFile: 'en_50k.txt', section: null),
    'ru': (freqFile: 'ru_50k.txt', section: 'Russian'),
    'zh': (freqFile: 'zh_50k.txt', section: 'Chinese'),
    'ja': (freqFile: 'ja_50k.txt', section: 'Japanese'),
    'es': (freqFile: 'es_50k.txt', section: 'Spanish'),
    'pt': (freqFile: 'pt_50k.txt', section: 'Portuguese'),
    'it': (freqFile: 'it_50k.txt', section: 'Italian'),
  };

  final wordNet = parseWordNet(sources);

  for (final MapEntry(key: lang, value: spec) in languages.entries) {
    final freqPath = '$sources/${spec.freqFile}';
    if (!File(freqPath).existsSync()) {
      stderr.writeln('$lang: missing $freqPath — skip');
      continue;
    }
    final words = readFreq(freqPath);
    await File('$work/${lang}_freq.tsv').writeAsString(
      words.map((final e) => '${e.$1}\t${e.$2}').join('\n'),
    );
    stderr.writeln('$lang: ${words.length} freq words');

    final section = spec.section;
    final wanted = words.map((final e) => e.$1).toList();
    // Definitions only for the TOP slice (3000) — the slice a keyboard's
    // chips/commit can actually reach; also the difference between a
    // polite 60-request fetch and a rate-limited 200-request one.
    final defTargets = wanted.take(defsTopWords).toList();
    final existing = _readExistingDefs('$work/${lang}_defs.tsv');
    final missing = defTargets
        .where((final word) => !existing.containsKey(word))
        .toList();
    final fetched = section == null
        ? glossesFor(wordNet, defTargets.toSet())
        : await wiktionaryGlosses(missing, section);
    final defs = <String, (String?, String)>{
      ...existing,
      for (final entry in fetched.entries) entry.key: entry.value,
    };
    await File('$work/${lang}_defs.tsv').writeAsString(
      defs.entries
          .map((final e) => '${e.key}\t${e.value.$1 ?? ''}\t${e.value.$2}')
          .join('\n'),
    );
    await File('$work/${lang}_source.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'language': lang,
        'frequency': <String, Object?>{
          'source': 'hermitdave/FrequencyWords (OpenSubtitles 2018/2016)',
          'license': 'CC-BY-SA 3.0',
          'file': spec.freqFile,
          'fetched': DateTime.now().toUtc().toIso8601String(),
        },
        'definitions': <String, Object?>{
          'source': section == null
              ? 'WordNet 3.1 (Princeton) glosses'
              : 'en.wiktionary.org "$section" sections — English '
                  'glosses in v1; native Wiktionaries are the upgrade path',
          'license': section == null
              ? 'WordNet 3.1 license (permissive)'
              : 'CC-BY-SA 4.0 (attribution required)',
          'fetched': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
    stderr.writeln('$lang: ${defs.length} definitions');
  }
}

const topWords = 10000;

/// Definitions are fetched only for this top slice per language.
const defsTopWords = 3000;

/// Already-fetched `word\tpos\tgloss` rows survive a re-run (the merge
/// makes the fetch resumable across rate-limit windows).
Map<String, (String?, String)> _readExistingDefs(final String path) {
  final file = File(path);
  if (!file.existsSync()) return <String, (String?, String)>{};
  final defs = <String, (String?, String)>{};
  for (final line in file.readAsLinesSync()) {
    final fields = line.split('\t');
    if (fields.length < 3) continue;
    defs[fields[0]] = (fields[1].isEmpty ? null : fields[1], fields[2]);
  }
  return defs;
}

/// `word count` lines → filtered, lowercased, capped at [topWords].
List<(String, int)> readFreq(final String path) {
  final isCJK = path.contains('/zh_') || path.contains('/ja_');
  final pattern = isCJK
      ? RegExp(r'^[⼀-鿿぀-ヿー・々]{1,12}$')
      : RegExp(r'^[a-zà-ÿа-яё]{2,}$', caseSensitive: false);
  final rows = <(String, int)>[];
  for (final line in File(path).readAsLinesSync()) {
    final space = line.lastIndexOf(' ');
    if (space <= 0) continue;
    final word = line.substring(0, space).toLowerCase();
    final count = int.tryParse(line.substring(space + 1)) ?? 0;
    if (count <= 0 || !pattern.hasMatch(word)) continue;
    rows.add((word, count));
    if (rows.length >= topWords) break;
  }
  return rows;
}

/// English Wiktionary glosses for [words], batched 50 titles/request.
Future<Map<String, (String?, String)>> wiktionaryGlosses(
  final List<String> words,
  final String section,
) async {
  final glosses = <String, (String?, String)>{};
  final client = HttpClient()..userAgent = 'universal_lexicon-builder';
  for (var start = 0; start < words.length; start += 50) {
    final end = start + 50 > words.length ? words.length : start + 50;
    final titles =
        words.sublist(start, end).map(Uri.encodeQueryComponent).join('|');
    final uri = Uri.parse(
      'https://en.wiktionary.org/w/api.php'
      '?action=query&format=json&formatversion=2'
      '&prop=revisions&rvprop=content&rvslots=main&titles=$titles',
    );
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (!body.startsWith('{')) {
        // Rate-limited (HTML error page / plain-text warning): back off
        // hard and retry once.
        await Future<void>.delayed(const Duration(seconds: 30));
        final retry = await client.getUrl(uri);
        final retryResponse = await retry.close();
        final retryBody = await retryResponse.transform(utf8.decoder).join();
        if (!retryBody.startsWith('{')) {
          stderr.writeln('  batch $start: still throttled — skipping');
          continue;
        }
        _collect(retryBody, section, glosses);
      } else {
        _collect(body, section, glosses);
      }
    } on Exception catch (error) {
      stderr.writeln('  batch $start: $error');
    }
    if (start % 500 == 0) stderr.writeln('  $section: $start…');
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
  client.close(force: true);
  return glosses;
}

void _collect(
  final String body,
  final String section,
  final Map<String, (String?, String)> glosses,
) {
  final page = jsonDecode(body) as Map<String, dynamic>;
  final query = page['query'] as Map<String, dynamic>?;
  final rawPages = query?['pages'] as List<dynamic>?;
  final pages = (rawPages ?? const <dynamic>[]).cast<Map<String, dynamic>>();
  for (final entry in pages) {
    final title = entry['title'] as String?;
    final revisions = entry['revisions'] as List<dynamic>?;
    final revision = revisions?.first as Map<String, dynamic>?;
    final slots = revision?['slots'] as Map<String, dynamic>?;
    final main = slots?['main'] as Map<String, dynamic>?;
    final content = main?['content'] as String?;
    if (title == null || content == null) continue;
    final gloss = firstGloss(content, section);
    if (gloss != null) glosses[title.toLowerCase()] = gloss;
  }
}

/// The first definition lines under `==[section]==`.
(String?, String)? firstGloss(final String wikitext, final String section) {
  final pattern = RegExp('^==\\s*$section\\s*==\\s*\$', multiLine: true);
  final header = pattern.firstMatch(wikitext);
  if (header == null) return null;
  var body = wikitext.substring(header.end);
  final next = RegExp(r'^==[^=].*==\s*$', multiLine: true).firstMatch(body);
  if (next != null) body = body.substring(0, next.start);

  String? pos;
  final defLines = <String>[];
  for (final line in body.split('\n')) {
    final posHeader = RegExp(r'^===?\s*([^=]+?)\s*===?\s*$').firstMatch(line);
    if (posHeader != null) {
      pos = posTag(posHeader.group(1)!.trim());
      continue;
    }
    if (RegExp('^#+[^#*:]').hasMatch(line)) {
      final cleaned = cleanWikitext(line.replaceFirst(RegExp(r'^#+\s*'), ''));
      if (cleaned.length < 3) continue;
      defLines.add(cleaned);
      if (defLines.length == 2) break;
    }
  }
  if (defLines.isEmpty) return null;
  final gloss = defLines.join(' — ');
  return (pos, gloss.substring(0, gloss.length > 140 ? 140 : gloss.length));
}

String cleanWikitext(final String raw) {
  var text = stripTemplates(raw);
  text = text.replaceAllMapped(
    RegExp(r'\[\[(?:[^\]|]*\|)?([^\]]+)\]\]'),
    (final match) => match.group(1)!,
  );
  return text
      .replaceAll(RegExp("''+"), '')
      .replaceAll(RegExp('<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String stripTemplates(final String input) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = 0; i < input.length; i++) {
    if (i + 1 < input.length && input[i] == '{' && input[i + 1] == '{') {
      depth++;
      i++;
      continue;
    }
    if (i + 1 < input.length && input[i] == '}' && input[i + 1] == '}') {
      if (depth > 0) depth--;
      i++;
      continue;
    }
    if (depth == 0) out.write(input[i]);
  }
  return out.toString();
}

String? posTag(final String header) => <String, String>{
      'noun': 'noun',
      'verb': 'verb',
      'adjective': 'adj',
      'adverb': 'adv',
      'pronoun': 'pron',
      'preposition': 'prep',
      'conjunction': 'conj',
      'interjection': 'interj',
      'particle': 'part',
      'numeral': 'num',
      'proper noun': 'propn',
      'phrase': 'phrase',
    }[header.toLowerCase()];

/// WordNet glosses restricted to the wanted words.
Map<String, (String?, String)> glossesFor(
  final Map<String, (String?, String)> wordNet,
  final Set<String> words,
) => <String, (String?, String)>{
      for (final word in words)
        if (wordNet[word] != null) word: wordNet[word]!,
    };

/// WordNet 3.1 (the nltk_data wordnet.zip, extracted to
/// `<sources>/wordnet/dict`): lemma → first-synset gloss.
Map<String, (String?, String)> parseWordNet(final String sources) {
  final dict = Directory('$sources/wordnet/dict');
  if (!dict.existsSync()) {
    stderr.writeln('wordnet: $sources/wordnet/dict missing — en defs skip');
    return const {};
  }
  final glossByOffset = <String, Map<int, String>>{};
  for (final entry in <String, String>{
    'n': 'data.noun',
    'v': 'data.verb',
    'a': 'data.adj',
    'r': 'data.adv',
  }.entries) {
    final map = <int, String>{};
    for (final line in File('${dict.path}/${entry.value}').readAsLinesSync()) {
      final pipe = line.indexOf('| ');
      if (pipe < 0) continue;
      final offset = int.tryParse(line.substring(0, line.indexOf(' ')));
      if (offset == null) continue;
      var gloss = line.substring(pipe + 2).trim();
      final semicolon = gloss.indexOf(';');
      if (semicolon > 0) gloss = gloss.substring(0, semicolon).trim();
      map[offset] = gloss;
    }
    glossByOffset[entry.key] = map;
  }

  final glosses = <String, (String?, String)>{};
  for (final entry in <String, ({String file, String pos})>{
    'n': (file: 'index.noun', pos: 'noun'),
    'v': (file: 'index.verb', pos: 'verb'),
    'a': (file: 'index.adj', pos: 'adj'),
    'r': (file: 'index.adv', pos: 'adv'),
  }.entries) {
    for (final line in File('${dict.path}/${entry.value.file}')
        .readAsLinesSync()) {
      if (line.startsWith('  ')) continue; // file header
      final fields = line.split(' ');
      if (fields.length < 9) continue;
      final lemma = fields[0].split('%').first.toLowerCase();
      // index format: lemma pos sense_cnt tag_cnt [ptrs…]
      // sense_cnt tagsense_cnt offset×sense_cnt — the offsets are the
      // trailing fields.
      final senseCount = int.tryParse(fields[2]) ?? 0;
      if (senseCount < 1 || fields.length < senseCount) continue;
      final offset = int.tryParse(fields[fields.length - senseCount]);
      final gloss =
          offset == null ? null : glossByOffset[entry.key]?[offset];
      if (gloss == null) continue;
      glosses.putIfAbsent(lemma, () => (entry.value.pos, gloss));
    }
  }
  stderr.writeln('wordnet: ${glosses.length} lemmas');
  return glosses;
}
