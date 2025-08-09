import 'package:universal_storage_interface/universal_storage_interface.dart';

/// {@template storage_provider_registry}
/// Registry for provider factories keyed by `StorageConfig` type.
///
/// This decouples the foundation from concrete providers. Provider packages
/// should register a factory at app startup, e.g.:
///
/// ```dart
/// // In your app bootstrap:
/// StorageProviderRegistry.register<FileSystemConfig>(
///   () => FileSystemStorageProvider(),
/// );
/// ```
///
/// Then `StorageFactory.create(config)` will resolve and initialize the
/// provider using the registered factory.
/// {@endtemplate}
abstract final class StorageProviderRegistry {
  static final Map<Type, StorageProvider Function()> _factories = {};

  /// Registers a provider factory for a `StorageConfig` subtype [T].
  static void register<T extends StorageConfig>(
    final StorageProvider Function() factory,
  ) {
    _factories[T] = factory;
  }

  /// Unregisters a factory for a `StorageConfig` subtype [T].
  static void unregister<T extends StorageConfig>() => _factories.remove(T);

  /// Clears all registered factories.
  static void clear() => _factories.clear();

  /// Resolves a provider instance for the given [config].
  /// Throws [ConfigurationException] if nothing is registered.
  static StorageProvider resolve(final StorageConfig config) {
    final factory = _factories[config.runtimeType];
    if (factory == null) {
      throw ConfigurationException(
        'No StorageProvider factory registered for ${config.runtimeType}.',
      );
    }
    return factory();
  }
}


