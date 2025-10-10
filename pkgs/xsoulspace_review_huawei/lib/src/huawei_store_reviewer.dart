import 'package:flutter/widgets.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template huawei_store_reviewer}
/// Store reviewer implementation for Huawei AppGallery.
///
/// Currently a placeholder implementation pending Huawei review API integration.
/// {@endtemplate}
final class HuaweiStoreReviewer extends StoreReviewer {
  /// {@macro huawei_store_reviewer}
  const HuaweiStoreReviewer();
  
  @override
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {
    // TODO(arenukvern): add implementation for Huawei AppGallery
  }
}

