import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Resolves profile namespaces to configured storage services.
abstract interface class StorageProfileResolver {
  Iterable<StorageNamespace> get namespaces;

  Future<StorageService> resolveService(final StorageNamespace namespace);

  Future<StorageCapabilities> resolveCapabilities(
    final StorageNamespace namespace,
  );
}

/// In-memory resolver for profile-based routing.
final class InMemoryStorageProfileResolver implements StorageProfileResolver {
  InMemoryStorageProfileResolver({
    required final Map<StorageNamespace, StorageService> namespaceServices,
    final Map<StorageNamespace, StorageCapabilities>? namespaceCapabilities,
  }) : _namespaceServices = Map.unmodifiable(namespaceServices),
       _namespaceCapabilities = Map.unmodifiable(
         namespaceCapabilities ??
             const <StorageNamespace, StorageCapabilities>{},
       );

  final Map<StorageNamespace, StorageService> _namespaceServices;
  final Map<StorageNamespace, StorageCapabilities> _namespaceCapabilities;

  @override
  Iterable<StorageNamespace> get namespaces => _namespaceServices.keys;

  @override
  Future<StorageService> resolveService(
    final StorageNamespace namespace,
  ) async {
    final service = _namespaceServices[namespace];
    if (service == null) {
      throw ConfigurationException(
        'No storage service configured for namespace: ${namespace.value}',
      );
    }
    return service;
  }

  @override
  Future<StorageCapabilities> resolveCapabilities(
    final StorageNamespace namespace,
  ) async => _namespaceCapabilities[namespace] ?? StorageCapabilities.none;
}
