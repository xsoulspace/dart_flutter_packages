import 'package:flutter/widgets.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

import 'logger_extensions.dart';
import 'store_review_requester.dart';

/// {@template review_foundation}
/// Main orchestrator for the review system.
///
/// This class coordinates the review system following the container pattern:
/// 1. Accepts [StoreReviewer] as dependency injection
/// 2. Manages [StoreReviewRequester] for scheduling
/// 3. Provides unified interface for review requests
///
/// ## Usage
/// ```dart
/// final foundation = ReviewFoundation(
///   storeReviewer: GoogleAppleStoreReviewer(),
///   requester: StoreReviewRequester(localDb: yourLocalDb),
///   logger: myLogger, // Optional
/// );
///
/// await foundation.init();
/// await foundation.requestReview(context);
/// ```
/// {@endtemplate}
class ReviewFoundation {
  /// {@macro review_foundation}
  ReviewFoundation({
    required this.storeReviewer,
    required this.requester,
    this.logger,
  });

  /// {@macro store_reviewer}
  final StoreReviewer storeReviewer;

  /// {@macro store_review_requester}
  final StoreReviewRequester requester;

  /// Optional logger for debugging and monitoring
  final Logger? logger;

  /// Initializes the review system.
  ///
  /// Calls [StoreReviewer.onLoad] and [StoreReviewRequester.onLoad]
  /// to prepare the review functionality.
  Future<void> init() async {
    logger.logReviewDebug('Initializing review foundation');
    try {
      await storeReviewer.onLoad();
      await requester.onLoad(storeReviewer: storeReviewer);
      logger.logReviewDebug('Review foundation initialized successfully');
    } catch (e, stack) {
      logger.logReviewError('Failed to initialize review foundation', e, stack);
      rethrow;
    }
  }

  /// Requests a review from the user.
  ///
  /// Delegates to [StoreReviewRequester.requestReview] which handles
  /// scheduling and count limits.
  ///
  /// [context] - Build context for showing dialogs if needed
  /// [locale] - Locale for localized consent dialogs
  /// [force] - If true, bypasses limits (for manual user-triggered reviews)
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) {
    logger.logReviewDebug(
      'Review requested via foundation',
      data: {'force': force, 'hasLocale': locale != null},
    );
    return requester.requestReview(context: context, locale: locale);
  }

  /// Disposes of resources.
  void dispose() {
    logger.logReviewDebug('Disposing review foundation');
    requester.dispose();
  }
}
