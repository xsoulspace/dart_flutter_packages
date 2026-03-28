import 'dart:convert';

import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Persistence interface for kernel decision states.
abstract interface class DecisionStore {
  /// Saves decision state by unique [decisionId].
  Future<void> saveState({
    required final String decisionId,
    required final DecisionState state,
    final String note = '',
  });

  /// Loads state for a single decision.
  Future<DecisionState?> loadState(final String decisionId);

  /// Loads all known decision states.
  Future<Map<String, DecisionState>> loadAllStates();
}

/// Default in-memory decision state store.
final class InMemoryDecisionStore implements DecisionStore {
  final Map<String, DecisionState> _states = <String, DecisionState>{};

  @override
  Future<void> saveState({
    required final String decisionId,
    required final DecisionState state,
    final String note = '',
  }) async {
    _states[decisionId] = state;
  }

  @override
  Future<DecisionState?> loadState(final String decisionId) async =>
      _states[decisionId];

  @override
  Future<Map<String, DecisionState>> loadAllStates() async =>
      Map<String, DecisionState>.unmodifiable(_states);
}

/// Storage-backed decision store for durable conflict history.
final class StorageServiceDecisionStore implements DecisionStore {
  StorageServiceDecisionStore({
    required this.storageService,
    required this.namespace,
    this.path = '.us/decisions.json',
  });

  /// Underlying service used to persist decisions.
  final StorageService storageService;

  /// Namespace where decision store is stored.
  final StorageNamespace namespace;

  /// File path for the serialized decision table.
  final String path;

  @override
  Future<void> saveState({
    required final String decisionId,
    required final DecisionState state,
    final String note = '',
  }) async {
    final current = await _loadStore();
    current[decisionId] = <String, String>{
      'state': state.name,
      'note': note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await storageService.saveFile(
      path,
      jsonEncode(_serializeStore(current)),
      message: 'Update decision state: $decisionId',
    );
  }

  @override
  Future<DecisionState?> loadState(final String decisionId) async {
    final states = await _loadStore();
    final rawState = states[decisionId]?['state'];
    if (rawState is! String || rawState.isEmpty) {
      return null;
    }

    return DecisionState.values.firstWhere(
      (final item) => item.name == rawState,
      orElse: () => DecisionState.autoResolved,
    );
  }

  @override
  Future<Map<String, DecisionState>> loadAllStates() async {
    final states = await _loadStore();
    final result = <String, DecisionState>{};

    for (final entry in states.entries) {
      final rawState = entry.value['state'];
      if (rawState is! String || rawState.isEmpty) {
        continue;
      }
      result[entry.key] = DecisionState.values.firstWhere(
        (final item) => item.name == rawState,
        orElse: () => DecisionState.autoResolved,
      );
    }

    return Map<String, DecisionState>.unmodifiable(result);
  }

  Future<Map<String, Map<String, String>>> _loadStore() async {
    final storedContent = await storageService.readFile(path);
    if (storedContent == null || storedContent.isEmpty) {
      return <String, Map<String, String>>{};
    }

    final Map<String, dynamic> raw;
    try {
      final decoded = jsonDecode(storedContent);
      if (decoded is! Map) {
        return <String, Map<String, String>>{};
      }
      raw = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return <String, Map<String, String>>{};
    }

    final result = <String, Map<String, String>>{};
    final decisions = raw['decisions'];
    if (decisions is! Map) {
      return result;
    }

    for (final rawEntry in decisions.entries) {
      final key = rawEntry.key.toString();
      final value = rawEntry.value;
      if (value is Map) {
        result[key] = <String, String>{
          for (final metadata in value.entries)
            metadata.key.toString(): metadata.value?.toString() ?? '',
        };
      }
    }

    return result;
  }

  Map<String, dynamic> _serializeStore(
    final Map<String, Map<String, String>> store,
  ) => <String, dynamic>{
    'schema_version': 1,
    'namespace': namespace.value,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'decisions': store,
  };
}
