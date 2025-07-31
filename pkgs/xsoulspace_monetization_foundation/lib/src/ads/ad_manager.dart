import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

/// {@template ad_manager}
/// Manages advertisements by delegating to a specific [AdProvider].
///
/// This class provides a clean interface for ad operations, abstracting
/// platform-specific implementations behind the [AdProvider] interface.
///
/// ## Supported Ad Types:
/// - **Rewarded Ads**: User gets reward for watching
/// - **Interstitial Ads**: Full-screen ads between app screens
/// - **Banner Ads**: Small ads displayed within app content
///
/// ## Usage
/// ```dart
/// final adManager = AdManager(yourAdProvider);
///
/// // Initialize ads
/// await adManager.init();
///
/// // Show rewarded ad
/// await adManager.showRewardedAd(adUnitId: 'rewarded_ad_unit');
///
/// // Build banner ad widget
/// final bannerWidget = adManager.buildBannerAd(
///   adUnitId: 'banner_ad_unit',
///   adSize: AdSize.banner,
/// );
/// ```
/// {@endtemplate}
class AdManager {
  AdManager(this.provider);
  final AdProvider provider;

  /// Initializes the ad provider and prepares it for use.
  Future<void> init() => provider.init();

  /// Shows a rewarded ad to the user.
  ///
  /// The user must watch the entire ad to receive the reward.
  /// Returns when the ad is completed or dismissed.
  Future<void> showRewardedAd({required final String adUnitId}) =>
      provider.showRewardedAd(adUnitId: adUnitId);

  /// Shows an interstitial ad to the user.
  ///
  /// Full-screen ad that can be dismissed by the user.
  /// Returns when the ad is completed or dismissed.
  Future<void> showInterstitialAd({required final String adUnitId}) =>
      provider.showInterstitialAd(adUnitId: adUnitId);

  /// Builds a banner ad widget for display within the app.
  ///
  /// Returns a widget that can be placed in the app's UI.
  /// The widget will automatically handle ad loading and display.
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) => provider.buildBannerAd(adUnitId: adUnitId, adSize: adSize);
}
