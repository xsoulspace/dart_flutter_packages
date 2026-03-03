import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_rustore_review/flutter_rustore_review.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template rustore_reviewer}
/// Store reviewer implementation for RuStore.
///
/// Uses the `flutter_rustore_review` package to display review prompts
/// for Russian app store.
/// {@endtemplate}
final class RuStoreReviewer extends StoreReviewer {
  /// {@macro rustore_reviewer}
  RuStoreReviewer({
    required this.consentBuilder,
    super.defaultLocale,
    super.packageName,
    final Future<void> Function()? requestReviewFlow,
    final Future<void> Function()? launchNativeReviewFlow,
    final Future<void> Function(String scheme)? launchSchemeAction,
  }) : _requestReviewFlow = requestReviewFlow ?? RustoreReviewClient.request,
       _launchNativeReviewFlow =
           launchNativeReviewFlow ?? RustoreReviewClient.review,
       _launchSchemeAction = launchSchemeAction;

  /// A builder for the consent screen when review limit is reached
  final ReviewerFallbackConsentBuilder consentBuilder;
  final Future<void> Function() _requestReviewFlow;
  final Future<void> Function() _launchNativeReviewFlow;
  final Future<void> Function(String scheme)? _launchSchemeAction;

  @override
  Future<bool> onLoad() async {
    await RustoreReviewClient.initialize();
    return true;
  }

  @override
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {
    try {
      await _requestReviewFlow();
      await _launchNativeReviewFlow();
    } on PlatformException catch (e) {
      switch (e.message) {
        case 'RuStoreRequestLimitReached':
          if (force && context.mounted) {
            final isConsent = await consentBuilder(
              context,
              locale ?? defaultLocale,
            );
            if (!isConsent) return;
            final scheme = 'https://www.rustore.ru/catalog/app/$packageName';
            final launchSchemeAction = _launchSchemeAction;
            if (launchSchemeAction != null) {
              await launchSchemeAction(scheme);
            } else {
              await launchScheme(scheme);
            }
          }
          return;
        case 'RuStoreReviewExists':
          // User already has a review
          return;
      }
      rethrow;
    }
  }
}
