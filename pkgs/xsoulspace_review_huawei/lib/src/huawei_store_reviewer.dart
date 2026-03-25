import 'package:flutter/widgets.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template huawei_store_reviewer}
/// Store reviewer implementation for Huawei AppGallery.
///
/// This implementation is intentionally a no-op fallback until a stable
/// Huawei review API is available for Flutter.
/// {@endtemplate}
final class HuaweiStoreReviewer extends StoreReviewer {
  /// {@macro huawei_store_reviewer}
  const HuaweiStoreReviewer();

  @override
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {}
}
