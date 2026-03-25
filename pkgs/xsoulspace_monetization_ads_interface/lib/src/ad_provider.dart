import 'package:flutter/widgets.dart';

/// {@template ad_provider}
/// An abstract interface for handling mobile advertisements.
///
/// This class defines the contract that all ad provider implementations
/// must adhere to, ensuring a consistent API for different ad networks.
/// {@endtemplate}
abstract class AdProvider {
  /// Initializes the ad provider.
  Future<void> init();

  /// Shows a rewarded ad.
  Future<void> showRewardedAd({required final String adUnitId});

  /// Shows an interstitial ad.
  Future<void> showInterstitialAd({required final String adUnitId});

  /// Builds a banner ad widget.
  Widget buildBannerAd({
    required final String adUnitId,
    required covariant final Object adSize,
  });
}
