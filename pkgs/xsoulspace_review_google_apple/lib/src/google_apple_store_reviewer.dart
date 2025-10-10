import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template google_apple_store_reviewer}
/// Store reviewer implementation for Google Play and Apple App Store.
///
/// Uses the `in_app_review` package to display native review prompts
/// on Android and iOS platforms.
/// {@endtemplate}
final class GoogleAppleStoreReviewer extends StoreReviewer {
  /// {@macro google_apple_store_reviewer}
  GoogleAppleStoreReviewer();

  final InAppReview _inAppReview = InAppReview.instance;

  @override
  Future<bool> onLoad() => _inAppReview.isAvailable();

  @override
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {
    if (await _inAppReview.isAvailable()) {
      await _inAppReview.requestReview();
    }
  }
}
