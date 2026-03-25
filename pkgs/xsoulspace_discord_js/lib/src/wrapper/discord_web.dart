import 'converters.dart';
import 'discord_client.dart';

export 'discord_client.dart';
export 'models.dart';

/// Wrapper entrypoint for Discord Embedded App SDK.
abstract final class Discord {
  static Future<DiscordClient> init({
    required final String clientId,
    final String expectedGlobal = 'DiscordSDK',
    final Map<String, Object?> configuration = const <String, Object?>{},
    final bool waitReady = true,
  }) async {
    final resolved = _resolveGlobal(expectedGlobal: expectedGlobal);
    if (resolved == null) {
      throw StateError(
        'Discord SDK constructor `$expectedGlobal` was not detected.',
      );
    }

    final sdk = _resolveSdkInstance(
      resolved: resolved,
      clientId: clientId,
      configuration: configuration,
    );
    if (sdk == null) {
      throw StateError('Discord SDK constructor returned null instance.');
    }

    final client = DiscordClient(sdk);
    if (waitReady) {
      await client.ready();
    }
    return client;
  }

  static bool isAvailable({final String expectedGlobal = 'DiscordSDK'}) {
    return _resolveGlobal(expectedGlobal: expectedGlobal) != null;
  }

  static Object? _resolveGlobal({required final String expectedGlobal}) {
    if (!hasGlobalProperty(expectedGlobal)) {
      return null;
    }
    return globalProperty(expectedGlobal);
  }

  static Object? _resolveSdkInstance({
    required final Object resolved,
    required final String clientId,
    required final Map<String, Object?> configuration,
  }) {
    if (prop(resolved, 'commands') != null && prop(resolved, 'ready') != null) {
      return resolved;
    }

    final args = <Object?>[clientId];
    if (configuration.isNotEmpty) {
      args.add(jsify(configuration));
    }
    return jsCallConstructor(resolved, args);
  }
}
