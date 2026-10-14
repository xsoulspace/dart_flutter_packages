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
  GoogleAppleStoreReviewer({
    Future<bool> Function()? isAvailable,
    Future<void> Function()? requestNativeReview,
  }) : _isAvailable = isAvailable ?? InAppReview.instance.isAvailable,
       _requestNativeReview =
           requestNativeReview ?? InAppReview.instance.requestReview;

  final Future<bool> Function() _isAvailable;
  final Future<void> Function() _requestNativeReview;

  @override
  Future<bool> onLoad() => _isAvailable();

  @override
  Future<void> requestReview(
    BuildContext context, {
    Locale? locale,
    bool force = false,
  }) async {
    if (await _isAvailable()) {
      await _requestNativeReview();
    }
  }
}
