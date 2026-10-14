import 'package:flutter/widgets.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template web_store_reviewer}
/// Store reviewer implementation for web platforms.
///
/// This implementation is intentionally a no-op fallback for web targets.
/// {@endtemplate}
final class WebStoreReviewer extends StoreReviewer {
  /// {@macro web_store_reviewer}
  const WebStoreReviewer();

  @override
  Future<void> requestReview(
    BuildContext context, {
    Locale? locale,
    bool force = false,
  }) async {}
}
