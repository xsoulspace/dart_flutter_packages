Map<String, Object?> buildApiDiff({
  required final Object? fromVersion,
  required final String toVersion,
  required final Set<String> oldSymbols,
  required final Set<String> newSymbols,
  final String fromVersionField = 'fromVersion',
  final String toVersionField = 'toVersion',
}) => <String, Object?>{
    fromVersionField: fromVersion,
    toVersionField: toVersion,
    'addedSymbols': (newSymbols.difference(oldSymbols).toList()..sort()),
    'removedSymbols': (oldSymbols.difference(newSymbols).toList()..sort()),
  };
