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
  const RuStoreReviewer({
    required this.consentBuilder,
    super.defaultLocale,
    super.packageName,
  });
  
  /// A builder for the consent screen when review limit is reached
  final ReviewerFallbackConsentBuilder consentBuilder;
  
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
      await RustoreReviewClient.request();
      await RustoreReviewClient.review();
    } on PlatformException catch (e) {
      switch (e.message) {
        case 'RuStoreRequestLimitReached':
          if (force && context.mounted) {
            final isConsent = await consentBuilder(
              context,
              locale ?? defaultLocale,
            );
            if (!isConsent) return;
            await launchScheme(
              'https://www.rustore.ru/catalog/app/$packageName',
            );
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

