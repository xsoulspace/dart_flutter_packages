import 'package:flutter/widgets.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

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
/// );
///
/// await foundation.init();
/// await foundation.requestReview(context);
/// ```
/// {@endtemplate}
class ReviewFoundation {
  /// {@macro review_foundation}
  ReviewFoundation({required this.storeReviewer, required this.requester});

  /// {@macro store_reviewer}
  final StoreReviewer storeReviewer;

  /// {@macro store_review_requester}
  final StoreReviewRequester requester;

  /// Initializes the review system.
  ///
  /// Calls [StoreReviewer.onLoad] and [StoreReviewRequester.onLoad]
  /// to prepare the review functionality.
  Future<void> init() async {
    await storeReviewer.onLoad();
    await requester.onLoad(storeReviewer: storeReviewer);
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
  }) => requester.requestReview(context: context, locale: locale);

  /// Disposes of resources.
  void dispose() => requester.dispose();
}
