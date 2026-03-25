import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

import 'capabilities.dart';
import 'noop_ad_provider.dart';

/// Wraps an existing [AdProvider] as a platform capability.
final class AdsCapabilityAdapter implements AdsCapability {
  const AdsCapabilityAdapter(this.adProvider);

  @override
  final AdProvider adProvider;

  @override
  String get capabilityName => 'monetization.ads';
}

/// No-op ads capability implementation.
final class NoopAdsCapability extends AdsCapabilityAdapter {
  NoopAdsCapability() : super(NoopAdProvider());
}
