# universal_lexicon

Offline dictionary logic for input methods (glide/shape keyboards,
prediction bars) and text tools: a [Lexicon][] of words + unigram
frequencies with ranked prefix candidates, and an offline
[DefinitionPack][] that serves word **definitions** with a constant
few-MB memory footprint — no network, no server, no full-dictionary
load.

Pure Dart. No Flutter dependency, no platform channels, no assets in
the package — the app ships its own data packs and hands bytes in.

## The lexicon

```dart
final lexicon = ListLexicon(
  words: ['hello', 'help', 'here', ...],
  frequencies: {'hello': 0.7, 'help': 0.75, 'here': 0.8, ...},
);

lexicon.prefixCandidates('hel'); // [here 0.8, help 0.75, hello 0.7]
lexicon.frequencyOf('world');    // 0.9 — the P(word) prior for decoders
```

Ranking semantics (shared by every consumer): **frequency first,
shorter word breaks ties**, then lexicographic. Comfortable to ~100k
words — prefix queries are a binary-search range scan, and the ranking
sort touches only the hits.

Corpus counts (OpenSubtitles, Google Ngrams, …) normalize to the 0..1
prior with [normalizeCounts][] — a **log** scale, because word
frequencies span orders of magnitude and linear mapping gives the top
ten words all the signal:

```dart
final prior = normalizeCounts(counts); // {'the': 1.0, 'obsidian': 0.05, …}
```

## Definitions, offline, in a few MB

The problem: dictionaries are huge (WordNet ~30 MB, Wiktionary
extracts gigabytes), and shipping them raw means either network calls
or a GB-resident process.

The design here: **you only need definitions for the words users can
actually produce** — the active vocabulary (a glide keyboard's lexicon
is ~2k–50k words), not the whole language. So:

- **Ship a curated pack, not the dictionary.** Top-N words per
  language, one short sense each (plus part of speech).
- **Block-compress it.** The file is zlib blocks of 64 entries,
  independently decompressable, behind a sorted 32-bit word-hash index
  (12 B/entry).
- **Constant-memory reads.** The app holds the compressed bytes (~2 MB
  for 50k entries), the eager index (~0.6 MB), and an LRU cache of 4
  decompressed blocks (~30 KB). Every lookup decompresses ONE block.
  Total resident: **~2–3 MB at any dictionary size** — no network, no
  server, by construction.

**Platforms**: the library is pure Dart with no `dart:io` in its
import graph — the default codec runs through `package:archive`
(native zlib on VM/Flutter, pure-Dart Inflate/Deflate on web), so the
SAME packs decode everywhere; cross-decode with native zlib and the
web path are test-pinned, and the package compiles to JavaScript and
runs (dart2js verified). Tools under `bin/` and `tool/` are build-time
and VM-only by nature.

```
// format v1 (little-endian), see lib/src/definition_pack_format.dart
header(24 B): 'LXDF' | version | blockCount | entryCount | indexOffset
data:         blockCount zlib blocks of `word\tpos\tdefinition\n` lines
index:        block spans, then (fnv1a32(word), blockId) sorted by hash
```

```dart
final bytes = /* the .lxdef file: load from an asset, mmap, or disk */;
final pack = DefinitionPack(bytes);            // parses header + index
pack.lookup('panda');  // [DefinitionEntry(noun, 'a bear native to …')]
pack.definition('glide'); // 'to move smoothly and continuously'
```

### Building a pack

Definitions live in a UTF-8 TSV (`word<TAB>pos<TAB>definition`, `#`
comments):

```sh
dart run universal_lexicon:build_definition_pack \
///   definitions.tsv definitions.lxdef
```

Verify what ships:

```sh
dart run example/definition_pack_smoke.dart definitions.lxdef panda zzz
```

Keep the provenance — source, license, extraction date — in a JSON
sidecar next to the pack; the pack itself stays data-only.

### Data sources (all offline-capable, per language)

| Need | Source | License |
| --- | --- | --- |
| Word + frequency ranking | [hermitdave/FrequencyWords][] (OpenSubtitles) | CC-BY-SA 3.0 |
| Word + frequency (alt) | Google Books Ngrams; `wordfreq` Zipf tables | varies / MIT |
| Definitions (English) | WordNet 3.1 glosses | permissive |
| Definitions (multi-language) | Wiktionary/Wiktextract extracts | CC-BY-SA 4.0 (attribute) |
| Spelling validity | hunspell wordlists | per-language |

For the first pack: take the top ~10k OpenSubtitles words of a
language, join definitions from WordNet (en) or Wiktextract (rest),
shorten to one sense ≤90 chars, keep frequency + definitions in the
same build script, record the source commit in the sidecar.

## Consumers

- **vosges glide keyboard** (`apps/desktop`): `ListLexicon` powers the
  prediction chips; `frequencyOf` is the P(word) prior in the shape
  decoder score; the language packs (below) feed both, and the
  committed word's gloss renders in the magic panel.

## Language packs (en ru zh ja es pt it)

Prebuilt packs live in `assets/glide/` — per language a **LexiconPack**
(`.lxlex`, top-10k words + log-normalized frequencies, ~50 KB) and
optionally a **DefinitionPack** (`.lxdef`, glosses for the top-3000
words), each with a provenance sidecar (`.json`: source, license,
fetch date).

Rebuild (two stages — fetch needs network once, build is offline and
resumable; re-running the fetch MERGES into existing TSVs, so each run
fills more of the rate-limited Wiktionary slices):

```sh
# stage 1 — sources into a work dir (frequency lists + wordnet.zip
# unzipped to sources/wordnet/dict; see tool/fetch_language_data.dart
# header for the exact URLs)
dart run tool/fetch_language_data.dart --sources sources --work work
# stage 2 — TSVs → packs (offline)
dart run bin/build_language_packs.dart --work work --out assets/glide
```

Sources: OpenSubtitles frequencies (CC-BY-SA) for all 7 languages;
WordNet 3.1 glosses (permissive) for en; English-Wiktionary glosses
(CC-BY-SA) for ru zh ja es pt it — **English glosses in v1**, native
Wiktionaries are the upgrade path; zh additionally carries a xinhua
placeholder slice (provenance gray — swap for CC-CEDICT). Coverage
note (2026-10-01): definitions landed for en (1569), ru (1179), zh
(1020), ja (372), es (71); it/pt ship lexicons without a .lxdef until
the fetch is re-run through the throttle window.

[Lexicon]: lib/src/lexicon.dart
[DefinitionPack]: lib/src/definition_pack.dart
[normalizeCounts]: lib/src/frequency.dart
[hermitdave/FrequencyWords]: https://github.com/hermitdave/FrequencyWords
