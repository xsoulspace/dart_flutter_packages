/// Offline dictionary logic: lexicon queries with unigram frequencies,
/// plus a block-compressed DefinitionPack that keeps definitions
/// on-device with a constant few-MB footprint.
library;

export 'src/block_codec.dart';
export 'src/definition_entry.dart';
export 'src/definition_pack.dart';
export 'src/definition_pack_builder.dart';
export 'src/definition_pack_format.dart';
export 'src/definition_store.dart';
export 'src/frequency.dart';
export 'src/lexicon.dart';
export 'src/lexicon_pack_format.dart';
export 'src/list_lexicon.dart';
export 'src/zlib_block_codec.dart';
