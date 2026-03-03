import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';
import 'package:xsoulspace_platform_ads_bridge/xsoulspace_platform_ads_bridge.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_crazygames_ads/xsoulspace_platform_crazygames_ads.dart';

void main() {
  test('adds ads capability when provider initializes', () async {
    final client = CrazyGamesAdsPlatformClient(
      baseClient: _FakeBaseClient(),
      pluginConfig: CrazyGamesAdsPluginConfig(
        adProviderFactory: () => _FakeAdProvider(),
      ),
      defaultProviderFactory: _FakeAdProvider.new,
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);
    expect(client.supports<AdsCapability>(), isTrue);
    expect(client.maybe<AdsCapability>(), isNotNull);
  });

  test('keeps base client active when ads init fails and optional', () async {
    final client = CrazyGamesAdsPlatformClient(
      baseClient: _FakeBaseClient(),
      pluginConfig: CrazyGamesAdsPluginConfig(
        adProviderFactory: () => _ThrowingAdProvider(),
      ),
      defaultProviderFactory: _FakeAdProvider.new,
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);
    expect(client.supports<AdsCapability>(), isFalse);
  });

  test('fails init when ads are required and provider throws', () async {
    final client = CrazyGamesAdsPlatformClient(
      baseClient: _FakeBaseClient(),
      pluginConfig: CrazyGamesAdsPluginConfig(
        failIfUnavailable: true,
        adProviderFactory: () => _ThrowingAdProvider(),
      ),
      defaultProviderFactory: _FakeAdProvider.new,
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isFailure, isTrue);
  });
}

final class _FakeBaseClient implements PlatformClient {
  @override
  PlatformId get platformId => PlatformId.crazyGames;

  @override
  Set<Type> get capabilityTypes => const <Type>{};

  @override
  Stream<PlatformEvent> get events => const Stream<PlatformEvent>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    return PlatformInitResult.success();
  }

  @override
  T? maybe<T extends PlatformCapability>() => null;

  @override
  T require<T extends PlatformCapability>() {
    throw MissingPlatformCapabilityException(
      capabilityType: T,
      supportedCapabilities: capabilityTypes,
      behavior: MissingCapabilityBehavior.strict,
      platformId: platformId,
    );
  }

  @override
  bool supports<T extends PlatformCapability>() => false;
}

final class _FakeAdProvider implements AdProvider {
  @override
  Future<void> init() async {}

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {}

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {}

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) {
    return const SizedBox.shrink();
  }
}

final class _ThrowingAdProvider extends _FakeAdProvider {
  @override
  Future<void> init() {
    throw StateError('ads unavailable');
  }
}
