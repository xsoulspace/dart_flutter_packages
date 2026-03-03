import 'package:meta/meta.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_monetization_yandex_games/xsoulspace_monetization_yandex_games.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_purchases_bridge/xsoulspace_platform_purchases_bridge.dart';
import 'package:xsoulspace_platform_yandex_games/xsoulspace_platform_yandex_games.dart';
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

@immutable
final class YandexGamesPurchasesPluginConfig {
  const YandexGamesPurchasesPluginConfig({
    this.signed = false,
    this.failIfUnavailable = false,
    this.purchaseProviderFactory,
  });

  final bool signed;
  final bool failIfUnavailable;
  final PurchaseProvider Function()? purchaseProviderFactory;
}

final class YandexGamesPurchasesPlatformFactory
    implements PlatformAdapterFactory {
  YandexGamesPurchasesPlatformFactory({
    required this.pluginConfig,
    this.baseConfig,
    this.priority = 0,
    this.environmentProbe,
    this.initClient,
  });

  final YandexGamesPurchasesPluginConfig pluginConfig;
  final YandexGamesPlatformConfig? baseConfig;

  @override
  final int priority;

  final bool Function()? environmentProbe;
  final Future<YsdkClient> Function({bool signed})? initClient;

  @override
  PlatformId get platformId => PlatformId.yandexGames;

  @override
  Future<bool> isSupportedEnvironment() async {
    return environmentProbe?.call() ?? true;
  }

  @override
  Future<PlatformClient> createClient() async {
    final init = initClient ?? YandexGames.init;
    final signed = pluginConfig.signed;

    final base = YandexGamesPlatformClient(
      config: baseConfig ?? YandexGamesPlatformConfig(signed: signed),
      initClient: init,
    );

    final defaultFactory = () =>
        YandexGamesPurchaseProvider(signed: signed, initClient: init);

    return YandexGamesPurchasesPlatformClient(
      baseClient: base,
      pluginConfig: pluginConfig,
      defaultProviderFactory: defaultFactory,
    );
  }
}

final class YandexGamesPurchasesPlatformClient implements PlatformClient {
  YandexGamesPurchasesPlatformClient({
    required final PlatformClient baseClient,
    required this.pluginConfig,
    required this.defaultProviderFactory,
  }) : _baseClient = baseClient;

  final PlatformClient _baseClient;
  final YandexGamesPurchasesPluginConfig pluginConfig;
  final PurchaseProvider Function() defaultProviderFactory;

  PurchaseProvider? _purchaseProvider;
  PurchasesCapability? _purchasesCapability;

  @override
  PlatformId get platformId => _baseClient.platformId;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    final baseResult = await _baseClient.init(options);
    if (!baseResult.isSuccess) {
      return baseResult;
    }

    final provider =
        pluginConfig.purchaseProviderFactory?.call() ??
        defaultProviderFactory();

    try {
      final status = await provider.init();
      if (status == MonetizationStoreStatus.notAvailable) {
        if (pluginConfig.failIfUnavailable) {
          await provider.dispose();
          return PlatformInitResult.failure(
            message: 'Yandex purchases plugin is not available.',
          );
        }
        await provider.dispose();
        return baseResult;
      }

      _purchaseProvider = provider;
      _purchasesCapability = PurchasesCapabilityAdapter(provider);
      return baseResult;
    } on Object catch (error) {
      await provider.dispose();
      if (pluginConfig.failIfUnavailable) {
        return PlatformInitResult.failure(
          message: 'Failed to initialize Yandex purchases plugin.',
          error: error,
        );
      }
      return baseResult;
    }
  }

  @override
  Future<void> dispose() async {
    final provider = _purchaseProvider;
    _purchaseProvider = null;
    _purchasesCapability = null;
    if (provider != null) {
      await provider.dispose();
    }
    await _baseClient.dispose();
  }

  @override
  bool supports<T extends PlatformCapability>() {
    if (_purchasesCapability is T) {
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
    final purchases = _tryCast<T>(_purchasesCapability);
    if (purchases != null) {
      return purchases;
    }
    return _baseClient.maybe<T>();
  }

  @override
  Set<Type> get capabilityTypes {
    final types = <Type>{..._baseClient.capabilityTypes};
    if (_purchasesCapability != null) {
      types.add(PurchasesCapability);
      types.add(_purchasesCapability!.runtimeType);
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
