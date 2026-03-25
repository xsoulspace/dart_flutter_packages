import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:yaml/yaml.dart';

/// Validation severity for a profile schema issue.
enum ProfileValidationSeverity {
  /// Schema validation error.
  error,

  /// Non-fatal schema warning.
  warning,
}

/// Structured schema issue.
@immutable
final class StorageProfileValidationIssue {
  /// Creates a schema issue entry.
  const StorageProfileValidationIssue({
    required this.severity,
    required this.code,
    required this.path,
    required this.message,
  });

  /// Severity of the issue.
  final ProfileValidationSeverity severity;

  /// Stable machine-readable code.
  final String code;

  /// Path inside profile payload.
  final String path;

  /// Human-readable message.
  final String message;

  /// Whether issue is an error.
  bool get isError => severity == ProfileValidationSeverity.error;

  /// Whether issue is a warning.
  bool get isWarning => severity == ProfileValidationSeverity.warning;

  @override
  String toString() => '[${severity.name}] $path ($code): $message';
}

/// Result of profile schema validation.
@immutable
final class StorageProfileValidationResult {
  /// Creates a validation result.
  const StorageProfileValidationResult({
    required this.issues,
    required this.normalizedMap,
  });

  /// Reported issues.
  final List<StorageProfileValidationIssue> issues;

  /// Normalized payload ready for [StorageProfile.fromJson].
  final Map<String, dynamic> normalizedMap;

  /// Whether profile has no validation errors.
  bool get isValid => !issues.any((final issue) => issue.isError);

  /// Validation errors.
  List<StorageProfileValidationIssue> get errors =>
      issues.where((final issue) => issue.isError).toList(growable: false);

  /// Validation warnings.
  List<StorageProfileValidationIssue> get warnings =>
      issues.where((final issue) => issue.isWarning).toList(growable: false);

  /// Compact summary for exceptions/logs.
  String summary() {
    if (issues.isEmpty) {
      return 'Profile is valid.';
    }
    return issues.map((final issue) => issue.toString()).join('\n');
  }
}

/// Schema validator and parser for profile v1 payloads.
final class StorageProfileSchemaValidator {
  /// Creates schema validator for a target profile version.
  const StorageProfileSchemaValidator({this.supportedVersion = 1});

  /// Supported profile major version.
  final int supportedVersion;

  /// Parses YAML payload and returns [StorageProfile] if validation passes.
  ///
  /// Throws [ConfigurationException] when YAML cannot be parsed or validation
  /// has errors.
  StorageProfile parseYaml(final String yamlSource) {
    final validation = validateYaml(yamlSource);
    if (!validation.isValid) {
      throw ConfigurationException(
        'Invalid storage profile schema.\n${validation.summary()}',
      );
    }
    return StorageProfile.fromJson(validation.normalizedMap);
  }

  /// Validates YAML payload and returns structured issues with normalized map.
  ///
  /// Throws [ConfigurationException] when YAML cannot be parsed.
  StorageProfileValidationResult validateYaml(final String yamlSource) {
    final dynamic decoded;
    try {
      decoded = loadYaml(yamlSource);
    } catch (e) {
      throw ConfigurationException('Invalid profile YAML: $e');
    }

    if (decoded is! YamlMap && decoded is! Map<dynamic, dynamic>) {
      throw const ConfigurationException(
        'Invalid profile YAML: top-level object must be a map.',
      );
    }

    final map = _toJsonMap(decoded);
    return validateMap(map);
  }

  /// Validates JSON-like map payload and returns parsed [StorageProfile].
  ///
  /// Throws [ConfigurationException] when validation has errors.
  StorageProfile parseMap(final Map<String, dynamic> payload) {
    final result = validateMap(payload);
    if (!result.isValid) {
      throw ConfigurationException(
        'Invalid storage profile schema.\n${result.summary()}',
      );
    }
    return StorageProfile.fromJson(result.normalizedMap);
  }

  /// Validates map payload and returns structured issues plus normalized map.
  StorageProfileValidationResult validateMap(
    final Map<String, dynamic> payload,
  ) {
    final issues = <StorageProfileValidationIssue>[];
    final normalized = Map<String, dynamic>.from(payload);

    const allowedTopKeys = <String>{
      'name',
      'version',
      'namespaces',
      'metadata',
    };
    for (final key in payload.keys) {
      if (!allowedTopKeys.contains(key)) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.warning,
            code: 'unknown_top_level_key',
            path: key,
            message: 'Unknown top-level key will be ignored by schema v1.',
          ),
        );
      }
    }

    final versionRaw = payload['version'];
    int version = supportedVersion;
    if (versionRaw == null) {
      issues.add(
        StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.warning,
          code: 'version_missing',
          path: 'version',
          message: 'Missing version. Defaults to $supportedVersion.',
        ),
      );
    } else if (versionRaw is int) {
      version = versionRaw;
      if (version <= 0) {
        issues.add(
          const StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'version_invalid',
            path: 'version',
            message: 'Version must be a positive integer.',
          ),
        );
      } else if (version != supportedVersion) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.warning,
            code: 'version_mismatch',
            path: 'version',
            message:
                'Schema v$version is parsed by v$supportedVersion validator.',
          ),
        );
      }
    } else {
      issues.add(
        const StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.error,
          code: 'version_type_invalid',
          path: 'version',
          message: 'Version must be an integer.',
        ),
      );
    }
    normalized['version'] = version;

    final profileName = (payload['name'] ?? '').toString().trim();
    if (profileName.isEmpty) {
      issues.add(
        const StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.error,
          code: 'name_missing',
          path: 'name',
          message: 'Profile name must be non-empty.',
        ),
      );
    }
    normalized['name'] = profileName;

    final metadata = payload['metadata'];
    if (metadata != null && metadata is! Map) {
      issues.add(
        const StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.error,
          code: 'metadata_type_invalid',
          path: 'metadata',
          message: 'metadata must be a map when provided.',
        ),
      );
    } else {
      normalized['metadata'] = metadata == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(metadata as Map<dynamic, dynamic>);
    }

    final namespaceRaw = payload['namespaces'];
    if (namespaceRaw is! List) {
      issues.add(
        const StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.error,
          code: 'namespaces_type_invalid',
          path: 'namespaces',
          message: 'namespaces must be a list.',
        ),
      );
      normalized['namespaces'] = const <Map<String, dynamic>>[];
      return StorageProfileValidationResult(
        issues: List<StorageProfileValidationIssue>.unmodifiable(issues),
        normalizedMap: normalized,
      );
    }

    if (namespaceRaw.isEmpty) {
      issues.add(
        const StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.error,
          code: 'namespaces_empty',
          path: 'namespaces',
          message: 'At least one namespace is required.',
        ),
      );
    }

    final seenNamespaces = <String>{};
    final normalizedNamespaces = <Map<String, dynamic>>[];

    for (var i = 0; i < namespaceRaw.length; i++) {
      final entryPath = 'namespaces[$i]';
      final entry = namespaceRaw[i];
      if (entry is! Map) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'namespace_entry_type_invalid',
            path: entryPath,
            message: 'Namespace entry must be a map.',
          ),
        );
        continue;
      }

      final map = Map<String, dynamic>.from(entry);
      final namespaceName = (map['namespace'] ?? '').toString().trim();
      if (namespaceName.isEmpty) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'namespace_missing',
            path: '$entryPath.namespace',
            message: 'Namespace value must be non-empty.',
          ),
        );
      } else if (!seenNamespaces.add(namespaceName)) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'namespace_duplicate',
            path: '$entryPath.namespace',
            message: 'Namespace "$namespaceName" is duplicated.',
          ),
        );
      }

      final policyRaw = (map['policy'] ?? '').toString();
      final normalizedPolicy = _normalizePolicy(policyRaw);
      if (normalizedPolicy == null) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'policy_invalid',
            path: '$entryPath.policy',
            message:
                'Unsupported policy "$policyRaw". Allowed: local_only,'
                ' optimistic_sync, remote_first, remote_only.',
          ),
        );
      } else {
        map['policy'] = normalizedPolicy;
      }

      final localEngineId = (map['local_engine_id'] ?? 'default')
          .toString()
          .trim();
      if (localEngineId.isEmpty) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'local_engine_id_empty',
            path: '$entryPath.local_engine_id',
            message: 'local_engine_id must be non-empty.',
          ),
        );
      }
      map['local_engine_id'] = localEngineId.isEmpty
          ? 'default'
          : localEngineId;

      final remoteEngineId = map['remote_engine_id']?.toString().trim();
      final policy = map['policy']?.toString() ?? '';
      if (_policyRequiresRemote(policy) &&
          (remoteEngineId == null || remoteEngineId.isEmpty)) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'remote_engine_required',
            path: '$entryPath.remote_engine_id',
            message: 'remote_engine_id is required for policy "$policy".',
          ),
        );
      }
      if (remoteEngineId != null && remoteEngineId.isNotEmpty) {
        map['remote_engine_id'] = remoteEngineId;
      } else {
        map.remove('remote_engine_id');
      }

      final interactionRaw = (map['sync_interaction_level'] ?? 'minimal')
          .toString();
      final normalizedInteraction = _normalizeInteraction(interactionRaw);
      if (normalizedInteraction == null) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'sync_interaction_level_invalid',
            path: '$entryPath.sync_interaction_level',
            message:
                'Unsupported interaction level "$interactionRaw".'
                ' Allowed: minimal, complex.',
          ),
        );
      } else {
        map['sync_interaction_level'] = normalizedInteraction;
      }

      final pathPrefix = (map['path_prefix'] ?? '').toString();
      if (pathPrefix.startsWith('/')) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.warning,
            code: 'path_prefix_absolute',
            path: '$entryPath.path_prefix',
            message: 'Absolute path prefix is discouraged; prefer relative.',
          ),
        );
      }

      final extension = (map['default_file_extension'] ?? '.json').toString();
      if (extension.isEmpty) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.warning,
            code: 'file_extension_empty',
            path: '$entryPath.default_file_extension',
            message:
                'Empty extension is allowed but may reduce discoverability.',
          ),
        );
      }
      map['default_file_extension'] = extension;

      final requiredCapabilitiesRaw = map['required_capabilities'];
      if (requiredCapabilitiesRaw != null && requiredCapabilitiesRaw is! Map) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'required_capabilities_type_invalid',
            path: '$entryPath.required_capabilities',
            message: 'required_capabilities must be a map when provided.',
          ),
        );
      } else {
        map['required_capabilities'] = requiredCapabilitiesRaw == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(
                requiredCapabilitiesRaw as Map<dynamic, dynamic>,
              );
      }

      final interaction =
          map['sync_interaction_level']?.toString() ?? 'minimal';
      if (interaction == SyncInteractionLevel.complex.name) {
        final requiredCapabilities = StorageCapabilities.fromJson(
          Map<String, dynamic>.from(
            map['required_capabilities'] as Map<String, dynamic>,
          ),
        );
        if (!requiredCapabilities.supportsComplexInteraction) {
          issues.add(
            StorageProfileValidationIssue(
              severity: ProfileValidationSeverity.warning,
              code: 'complex_capabilities_incomplete',
              path: '$entryPath.required_capabilities',
              message:
                  'Complex interaction requested but required capabilities do'
                  ' not include full diff/history/revision/conflict set.'
                  ' Runtime may downgrade to minimal.',
            ),
          );
        }
      }

      final queuePolicyRaw = map['queue_policy'];
      if (queuePolicyRaw != null && queuePolicyRaw is! Map) {
        issues.add(
          StorageProfileValidationIssue(
            severity: ProfileValidationSeverity.error,
            code: 'queue_policy_type_invalid',
            path: '$entryPath.queue_policy',
            message: 'queue_policy must be a map when provided.',
          ),
        );
      } else if (queuePolicyRaw is Map) {
        final queuePolicy = Map<String, dynamic>.from(
          queuePolicyRaw as Map<dynamic, dynamic>,
        );
        _validatePositiveInt(
          queuePolicy,
          key: 'max_retries',
          path: '$entryPath.queue_policy.max_retries',
          issues: issues,
        );
        _validatePositiveInt(
          queuePolicy,
          key: 'initial_backoff_ms',
          path: '$entryPath.queue_policy.initial_backoff_ms',
          issues: issues,
        );
        _validatePositiveInt(
          queuePolicy,
          key: 'max_backoff_ms',
          path: '$entryPath.queue_policy.max_backoff_ms',
          issues: issues,
        );
        _validatePositiveInt(
          queuePolicy,
          key: 'max_entry_age_ms',
          path: '$entryPath.queue_policy.max_entry_age_ms',
          issues: issues,
        );
        map['queue_policy'] = queuePolicy;
      }

      normalizedNamespaces.add(map);
    }

    normalized['namespaces'] = normalizedNamespaces;
    return StorageProfileValidationResult(
      issues: List<StorageProfileValidationIssue>.unmodifiable(issues),
      normalizedMap: normalized,
    );
  }

  Map<String, dynamic> _toJsonMap(final Object? node) {
    if (node is YamlMap) {
      return node.map(
        (final key, final value) =>
            MapEntry(key.toString(), _toJsonNode(value)),
      );
    }
    if (node is Map<dynamic, dynamic>) {
      return node.map(
        (final key, final value) =>
            MapEntry(key.toString(), _toJsonNode(value)),
      );
    }
    throw const ConfigurationException(
      'Invalid profile payload: top-level object must be a map.',
    );
  }

  Object? _toJsonNode(final Object? node) {
    if (node is YamlMap || node is Map<dynamic, dynamic>) {
      return _toJsonMap(node);
    }
    if (node is YamlList) {
      return node.map(_toJsonNode).toList();
    }
    if (node is List<Object?>) {
      return node.map(_toJsonNode).toList();
    }
    if (node is List) {
      return node.map<Object?>(_toJsonNode).toList();
    }
    return node;
  }

  String? _normalizePolicy(final String raw) {
    final compact = raw.trim();
    if (compact.isEmpty) {
      return null;
    }
    const mapping = <String, String>{
      'localOnly': 'localOnly',
      'local_only': 'localOnly',
      'optimisticSync': 'optimisticSync',
      'optimistic_sync': 'optimisticSync',
      'remoteFirst': 'remoteFirst',
      'remote_first': 'remoteFirst',
      'remoteOnly': 'remoteOnly',
      'remote_only': 'remoteOnly',
    };
    return mapping[compact];
  }

  String? _normalizeInteraction(final String raw) {
    final compact = raw.trim();
    if (compact.isEmpty) {
      return null;
    }
    const mapping = <String, String>{
      'minimal': 'minimal',
      'complex': 'complex',
    };
    return mapping[compact];
  }

  bool _policyRequiresRemote(final String policyName) =>
      policyName == StoragePolicy.optimisticSync.name ||
      policyName == StoragePolicy.remoteFirst.name ||
      policyName == StoragePolicy.remoteOnly.name;

  void _validatePositiveInt(
    final Map<String, dynamic> map, {
    required final String key,
    required final String path,
    required final List<StorageProfileValidationIssue> issues,
  }) {
    if (!map.containsKey(key)) {
      return;
    }

    final raw = map[key];
    int? value;
    if (raw is int) {
      value = raw;
    } else if (raw is num) {
      value = raw.toInt();
    } else if (raw is String) {
      value = int.tryParse(raw.trim());
    }

    if (value == null || value <= 0) {
      issues.add(
        StorageProfileValidationIssue(
          severity: ProfileValidationSeverity.error,
          code: 'queue_policy_value_invalid',
          path: path,
          message: '$key must be a positive integer.',
        ),
      );
      return;
    }

    map[key] = value;
  }
}
