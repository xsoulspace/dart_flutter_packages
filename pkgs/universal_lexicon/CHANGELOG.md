# Changelog

## 0.1.0-dev.3

- `Lexicon.fuzzyPrefixCandidates`: the NOISY-prefix query — a word
  qualifies when the edit distance between the probe and the word's
  same-length head is within the cap; ranked distance-first, then the
  family's frequency order. Bounded Levenshtein with an early-exit row
  minimum keeps a 50k-word scan at one-shot latency. The glide
  keyboard's completion tier needed it: strict prefixes silently refuse
  everything a real hand writes (`helo` matches no prefix of anything).
## 0.1.0-dev.1

- Initial release: `Lexicon` interface + `ListLexicon` (sorted list,
  binary-search prefix candidates ranked by unigram frequency),
  `normalizeCounts` log-scale count normalization, and the offline
  `DefinitionPack` (format v1): block-compressed zlib storage, 32-bit
  word-hash index, LRU block cache — constant few-MB memory, no
  network, no server.
- `build_definition_pack` tool: TSV → `.lxdef`.

- `universal_io` replaces `dart:io` in lib/ and tools.
- `LexiconPack` format v1 (`LXLP`): fast-boot word + frequency packs.
- Language packs for en ru zh ja es pt it in `assets/glide/` with
  provenance sidecars; `tool/fetch_language_data.dart` (network,
  resumable) + `bin/build_language_packs.dart` (offline).
- `DefinitionPack.readAll()` bulk read.

## 0.1.0-dev.2

- **WEB**: the default `ZLibBlockCodec` now runs through
  `package:archive` — native zlib on VM/Flutter, pure-Dart
  Inflate/Deflate on web. One codec works everywhere; packs are
  byte-compatible across platforms (pinned by cross-decode tests and
  the `ZLibDecoderWeb`/`ZLibEncoderWeb` path test). Removed the
  unused `level` parameter (archive's encoder takes none).
- Verified: the library compiles to JavaScript (dart2js) and runs —
  build + read + prefix query on a pure JS runtime.
