import 'package:flutter/widgets.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template web_store_reviewer}
/// Store reviewer implementation for web platforms.
///
/// Currently a placeholder implementation for web review functionality.
/// {@endtemplate}
final class WebStoreReviewer extends StoreReviewer {
  /// {@macro web_store_reviewer}
  const WebStoreReviewer();
  
  @override
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {
    // TODO(arenukvern): add review request for web
  }
}

