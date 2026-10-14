Map<String, Object?> buildApiDiff({
  required Object? fromVersion,
  required String toVersion,
  required Set<String> oldSymbols,
  required Set<String> newSymbols,
  String fromVersionField = 'fromVersion',
  String toVersionField = 'toVersion',
}) => <String, Object?>{
  fromVersionField: fromVersion,
  toVersionField: toVersion,
  'addedSymbols': (newSymbols.difference(oldSymbols).toList()..sort()),
  'removedSymbols': (oldSymbols.difference(newSymbols).toList()..sort()),
};
