import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'decision_store.dart';
import 'storage_kernel.dart';
import 'storage_profile_resolver.dart';

/// Factory function that builds a storage service for one namespace profile.
typedef NamespaceServiceFactory =
    Future<StorageService> Function(StorageNamespaceProfile namespaceProfile);

/// Optional function resolving runtime capabilities for a namespace service.
typedef NamespaceCapabilitiesFactory =
    Future<StorageCapabilities> Function(
      StorageNamespaceProfile namespaceProfile,
      StorageService service,
    );

/// Result of loading a profile into a ready [StorageKernel].
@immutable
final class StorageProfileLoadResult {
  /// Creates profile load result.
  const StorageProfileLoadResult({
    required this.profile,
    required this.kernel,
    this.warnings = const <String>[],
  });

  /// Loaded and normalized profile.
  final StorageProfile profile;

  /// Ready-to-use storage kernel.
  final StorageKernel kernel;

  /// Non-fatal load warnings.
  final List<String> warnings;
}

/// Loads [StorageProfile] payloads and wires them into [StorageKernel].
final class StorageProfileLoader {
  /// Creates profile loader with optional kernel orchestration plugins.
  const StorageProfileLoader({
    this.syncEngine,
    this.migrationEndpoint,
    this.decisionStore,
  });

  /// Optional sync orchestrator for created kernels.
  final SyncEngine? syncEngine;

  /// Optional migration endpoint for created kernels.
  final MigrationEndpoint? migrationEndpoint;

  /// Optional decision store used by created kernels.
  final DecisionStore? decisionStore;

  /// Builds a kernel from a [StorageProfile].
  ///
  /// [serviceFactory] must provide one initialized [StorageService] per
  /// namespace profile.
  Future<StorageProfileLoadResult> load({
    required final StorageProfile profile,
    required final NamespaceServiceFactory serviceFactory,
    final NamespaceCapabilitiesFactory? capabilitiesFactory,
    final bool strict = true,
    final List<String> initialWarnings = const <String>[],
  }) async {
    final validationIssues = _validateProfile(profile);
    if (strict && validationIssues.any((final issue) => issue.isError)) {
      throw ConfigurationException(_formatProfileIssues(validationIssues));
    }

    final warnings = <String>[
      ...initialWarnings,
      ...validationIssues
          .where((final issue) => !issue.isError)
          .map((final issue) => issue.message),
    ];

    final namespaceServices = <StorageNamespace, StorageService>{};
    final namespaceCapabilities = <StorageNamespace, StorageCapabilities>{};

    for (final namespaceProfile in profile.namespaces) {
      final namespace = namespaceProfile.namespace;
      if (namespaceServices.containsKey(namespace)) {
        continue;
      }

      final service = await serviceFactory(namespaceProfile);
      namespaceServices[namespace] = service;

      final capabilities = capabilitiesFactory == null
          ? _defaultCapabilities(service)
          : await capabilitiesFactory(namespaceProfile, service);
      namespaceCapabilities[namespace] = capabilities;
    }

    final resolver = InMemoryStorageProfileResolver(
      namespaceServices: namespaceServices,
      namespaceCapabilities: namespaceCapabilities,
    );
    final kernel = StorageKernel(
      profile: profile,
      resolver: resolver,
      syncEngine: syncEngine,
      migrationEndpoint: migrationEndpoint,
      decisionStore: decisionStore,
    );

    return StorageProfileLoadResult(
      profile: profile,
      kernel: kernel,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  /// Parses profile from a map and builds kernel.
  Future<StorageProfileLoadResult> loadFromMap({
    required final Map<String, dynamic> profileMap,
    required final NamespaceServiceFactory serviceFactory,
    final NamespaceCapabilitiesFactory? capabilitiesFactory,
    final bool strict = true,
    final List<String> initialWarnings = const <String>[],
  }) {
    final profile = StorageProfile.fromJson(profileMap);
    return load(
      profile: profile,
      serviceFactory: serviceFactory,
      capabilitiesFactory: capabilitiesFactory,
      strict: strict,
      initialWarnings: initialWarnings,
    );
  }

  /// Parses profile from JSON source and builds kernel.
  Future<StorageProfileLoadResult> loadFromJson({
    required final String jsonSource,
    required final NamespaceServiceFactory serviceFactory,
    final NamespaceCapabilitiesFactory? capabilitiesFactory,
    final bool strict = true,
    final List<String> initialWarnings = const <String>[],
  }) {
    final decoded = jsonDecode(jsonSource);
    if (decoded is! Map) {
      throw const ConfigurationException(
        'Invalid profile JSON: top-level object must be a map.',
      );
    }

    return loadFromMap(
      profileMap: Map<String, dynamic>.from(decoded),
      serviceFactory: serviceFactory,
      capabilitiesFactory: capabilitiesFactory,
      strict: strict,
      initialWarnings: initialWarnings,
    );
  }

  StorageCapabilities _defaultCapabilities(final StorageService service) {
    final provider = service.provider;
    final supportsSync = provider.supportsSync;
    if (provider is RemoteEngine) {
      return provider.declaredCapabilities;
    }
    return StorageCapabilities(supportsBackgroundSync: supportsSync);
  }

  List<_ProfileLoadIssue> _validateProfile(final StorageProfile profile) {
    final issues = <_ProfileLoadIssue>[];
    if (profile.name.trim().isEmpty) {
      issues.add(
        const _ProfileLoadIssue(
          isError: true,
          message: 'Profile name must be non-empty.',
        ),
      );
    }
    if (profile.namespaces.isEmpty) {
      issues.add(
        const _ProfileLoadIssue(
          isError: true,
          message: 'At least one namespace profile is required.',
        ),
      );
      return issues;
    }

    final seen = <StorageNamespace>{};
    for (final namespaceProfile in profile.namespaces) {
      if (!seen.add(namespaceProfile.namespace)) {
        issues.add(
          _ProfileLoadIssue(
            isError: true,
            message:
                'Duplicate namespace detected: '
                '${namespaceProfile.namespace.value}.',
          ),
        );
      }
      if (namespaceProfile.localEngineId.trim().isEmpty) {
        issues.add(
          _ProfileLoadIssue(
            isError: true,
            message:
                'Namespace "${namespaceProfile.namespace.value}" '
                'has empty localEngineId.',
          ),
        );
      }
      if (namespaceProfile.requiresRemote &&
          (namespaceProfile.remoteEngineId == null ||
              namespaceProfile.remoteEngineId!.trim().isEmpty)) {
        issues.add(
          _ProfileLoadIssue(
            isError: true,
            message:
                'Namespace "${namespaceProfile.namespace.value}" '
                'requires remoteEngineId for policy '
                '"${namespaceProfile.policy.name}".',
          ),
        );
      }
      if (namespaceProfile.syncInteractionLevel ==
              SyncInteractionLevel.complex &&
          !namespaceProfile.requiredCapabilities.supportsComplexInteraction) {
        issues.add(
          _ProfileLoadIssue(
            isError: false,
            message:
                'Namespace "${namespaceProfile.namespace.value}" requests '
                'complex interaction without full required capabilities; '
                'runtime may degrade to minimal.',
          ),
        );
      }
    }

    return issues;
  }

  String _formatProfileIssues(final List<_ProfileLoadIssue> issues) {
    final buffer = StringBuffer('Invalid storage profile configuration.');
    for (final issue in issues.where((final issue) => issue.isError)) {
      buffer
        ..writeln()
        ..write('- ')
        ..write(issue.message);
    }
    return buffer.toString();
  }
}

@immutable
final class _ProfileLoadIssue {
  const _ProfileLoadIssue({required this.isError, required this.message});

  final bool isError;
  final String message;
}
