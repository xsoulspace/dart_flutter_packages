import 'package:meta/meta.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

import 'profile_schema_validator.dart';

/// Loads storage kernel from YAML profile using schema validation.
@immutable
final class YamlStorageProfileLoader {
  /// Creates YAML loader with configurable validator and kernel loader.
  const YamlStorageProfileLoader({
    this.validator = const StorageProfileSchemaValidator(),
    this.loader = const StorageProfileLoader(),
  });

  /// Profile schema validator.
  final StorageProfileSchemaValidator validator;

  /// Kernel/profile loader.
  final StorageProfileLoader loader;

  /// Validates profile YAML and builds [StorageKernel].
  ///
  /// Validation warnings are appended to kernel load warnings.
  Future<StorageProfileLoadResult> load({
    required final String yamlSource,
    required final NamespaceServiceFactory serviceFactory,
    final NamespaceCapabilitiesFactory? capabilitiesFactory,
    final bool strict = true,
  }) {
    final validation = validator.validateYaml(yamlSource);
    if (!validation.isValid) {
      throw ConfigurationException(
        'Invalid storage profile schema.\n${validation.summary()}',
      );
    }

    final profile = StorageProfile.fromJson(validation.normalizedMap);
    final validationWarnings = validation.warnings
        .map((final issue) => '${issue.path}: ${issue.message}')
        .toList(growable: false);

    return loader.load(
      profile: profile,
      serviceFactory: serviceFactory,
      capabilitiesFactory: capabilitiesFactory,
      strict: strict,
      initialWarnings: validationWarnings,
    );
  }

  /// Returns validation diagnostics without building kernel.
  StorageProfileValidationResult validate(final String yamlSource) =>
      validator.validateYaml(yamlSource);
}
