import 'package:meta/meta.dart';

/// One dictionary sense: a word, its part of speech, and its definition.
@immutable
final class DefinitionEntry {
  const DefinitionEntry({
    required this.word,
    required this.definition,
    this.partOfSpeech,
  });

  /// Lowercase headword.
  final String word;

  /// e.g. `noun`, `verb` — free-form, may be null.
  final String? partOfSpeech;

  /// The sense text, plain UTF-8 (no markup).
  final String definition;

  @override
  String toString() =>
      'DefinitionEntry($word, ${partOfSpeech ?? '-'}, $definition)';

  @override
  bool operator ==(final Object other) =>
      other is DefinitionEntry &&
      other.word == word &&
      other.partOfSpeech == partOfSpeech &&
      other.definition == definition;

  @override
  int get hashCode => Object.hash(word, partOfSpeech, definition);
}
