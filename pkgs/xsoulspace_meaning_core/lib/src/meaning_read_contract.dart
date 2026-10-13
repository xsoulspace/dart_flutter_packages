/// Existing meaning-program vocabulary and compatibility defaults.
/// Hosts may choose tighter tier budgets; this library never dispatches tools.
const meaningReadProgramOps = <String>['locate', 'zoom', 'impact', 'read'];
const programMaxOps = 8;
const perOpResultBudgetTokens = 512;
const defaultProgramVerdictBudgetTokens = 1200;
const programCursorCap = 8;

typedef MeaningOpResultProjection =
    Map<String, dynamic> Function(String op, Map<String, dynamic> result);

/// Exact existing pre-dispatch refusal envelope, or null for an admissible
/// envelope. Individual operations validate lazily, preserving fail-fast
/// execution and results-so-far. Optional budgets retain host fallback rules.
Map<String, dynamic>? meaningProgramEnvelopeRefusal(Object? ops) {
  if (ops is! List || ops.isEmpty) {
    return {
      'ok': false,
      'program_halt': {
        'index': 0,
        'error': 'ops_required',
        'hint': 'ops is a non-empty array of {op: locate|zoom|impact|read}',
      },
    };
  }
  if (ops.length > programMaxOps) {
    return {
      'ok': false,
      'program_halt': {
        'index': 0,
        'error': 'too_many_ops: ${ops.length} > $programMaxOps',
        'hint':
            'split the work across decisions — the next decision '
            'sees this verdict',
      },
    };
  }
  return null;
}

/// Only validates the closed vocabulary. Native argument schemas and cursor
/// requirements remain with their owners, including registered effect ops.
String? meaningProgramOpError(Object? op, Iterable<String> hostOps) {
  if (op is String &&
      (meaningReadProgramOps.contains(op) || hostOps.contains(op))) {
    return null;
  }
  final registered = hostOps.isEmpty
      ? ''
      : ' + registered: ${hostOps.toList()}';
  return 'unknown_op — closed set: $meaningReadProgramOps$registered';
}
