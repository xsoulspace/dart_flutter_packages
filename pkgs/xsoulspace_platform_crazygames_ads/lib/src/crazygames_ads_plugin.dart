import 'package:meta/meta.dart';
import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';
import 'package:xsoulspace_monetization_ads_crazygames/xsoulspace_monetization_ads_crazygames.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';
import 'package:xsoulspace_platform_ads_bridge/xsoulspace_platform_ads_bridge.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_crazygames/xsoulspace_platform_crazygames.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';

@immutable
final class CrazyGamesAdsPluginConfig {
  const CrazyGamesAdsPluginConfig({
    this.failIfUnavailable = false,
    this.adProviderFactory,
  });

  final bool failIfUnavailable;
  final AdProvider Function()? adProviderFactory;
}

final class CrazyGamesAdsPlatformFactory implements PlatformAdapterFactory {
  CrazyGamesAdsPlatformFactory({
    required this.pluginConfig,
    this.baseConfig,
    this.priority = 0,
    this.environmentProbe,
    this.initClient,
  });

  final CrazyGamesAdsPluginConfig pluginConfig;
  final CrazyGamesPlatformConfig? baseConfig;

  @override
  final int priority;

  final bool Function(String expectedGlobal)? environmentProbe;
  final CrazyGamesClientInitializer? initClient;

  @override
  PlatformId get platformId => PlatformId.crazyGames;

  @override
  Future<bool> isSupportedEnvironment() async {
    final effectiveConfig = baseConfig ?? const CrazyGamesPlatformConfig();

    final probe = environmentProbe;
    if (probe != null) {
      return probe(effectiveConfig.expectedSdkGlobal);
    }

    final injected = effectiveConfig.sdkInjected;
    if (injected != null) {
      return injected;
    }

    if (effectiveConfig.autoLoadSdk &&
        effectiveConfig.sdkScriptLoader != null &&
        effectiveConfig.sdkUrl != null) {
      return true;
    }

    return CrazyGames.isAvailable(
      expectedGlobal: effectiveConfig.expectedSdkGlobal,
    );
  }

  @override
  Future<PlatformClient> createClient() async {
    final init = initClient ?? CrazyGames.init;
    final effectiveBaseConfig = baseConfig ?? const CrazyGamesPlatformConfig();

    final base = CrazyGamesPlatformClient(
      config: effectiveBaseConfig,
      initClient: init,
    );

    final defaultFactory = () => CrazyGamesAdProvider(
      expectedGlobal: effectiveBaseConfig.expectedSdkGlobal,
      initClient: init,
    );

    return CrazyGamesAdsPlatformClient(
      baseClient: base,
      pluginConfig: pluginConfig,
      defaultProviderFactory: defaultFactory,
    );
  }
}

final class CrazyGamesAdsPlatformClient implements PlatformClient {
  CrazyGamesAdsPlatformClient({
    required final PlatformClient baseClient,
    required this.pluginConfig,
    required this.defaultProviderFactory,
  }) : _baseClient = baseClient;

  final PlatformClient _baseClient;
  final CrazyGamesAdsPluginConfig pluginConfig;
  final AdProvider Function() defaultProviderFactory;

  AdsCapability? _adsCapability;
  var _disposed = false;

  @override
  PlatformId get platformId => _baseClient.platformId;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    final baseResult = await _baseClient.init(options);
    if (!baseResult.isSuccess) {
      return baseResult;
    }

    final provider =
        pluginConfig.adProviderFactory?.call() ?? defaultProviderFactory();

    try {
      await provider.init();
      _adsCapability = AdsCapabilityAdapter(provider);
      return baseResult;
    } on Object catch (error) {
      if (pluginConfig.failIfUnavailable) {
        return PlatformInitResult.failure(
          message: 'Failed to initialize CrazyGames ads plugin.',
          error: error,
        );
      }
      return baseResult;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _adsCapability = null;
    await _baseClient.dispose();
  }

  @override
  bool supports<T extends PlatformCapability>() {
    if (_adsCapability is T) {
      return true;
    }
    return _baseClient.supports<T>();
  }

  @override
  T require<T extends PlatformCapability>() {
    final capability = maybe<T>();
    if (capability == null) {
      throw MissingPlatformCapabilityException(
        capabilityType: T,
        supportedCapabilities: capabilityTypes,
        behavior: MissingCapabilityBehavior.strict,
        platformId: platformId,
      );
    }
    return capability;
  }

  @override
  T? maybe<T extends PlatformCapability>() {
    final ads = _tryCast<T>(_adsCapability);
    if (ads is T) {
      return ads;
    }
    return _baseClient.maybe<T>();
  }

  @override
  Set<Type> get capabilityTypes {
    final types = <Type>{..._baseClient.capabilityTypes};
    if (_adsCapability != null) {
      types.add(AdsCapability);
      types.add(_adsCapability!.runtimeType);
    }
    return Set<Type>.unmodifiable(types);
  }

  @override
  Stream<PlatformEvent> get events => _baseClient.events;

  T? _tryCast<T>(final Object? value) {
    if (value is T) {
      return value;
    }
    return null;
  }
}
