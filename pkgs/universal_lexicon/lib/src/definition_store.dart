import 'definition_entry.dart';

/// The abstract offline definitions source.
abstract interface class DefinitionStore {
  /// All senses of [word] (lowercase), empty when unknown.
  List<DefinitionEntry> lookup(final String word);

  /// The first definition text for [word], null when unknown.
  String? definition(final String word);
}
