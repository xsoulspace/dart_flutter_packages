import 'package:flutter/widgets.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

/// {@template snapstore_reviewer}
/// Store reviewer implementation for Linux Snap Store.
///
/// Launches the snap review scheme with a consent dialog.
/// {@endtemplate}
final class SnapStoreReviewer extends StoreReviewer {
  /// {@macro snapstore_reviewer}
  SnapStoreReviewer({
    required super.packageName,
    required this.consentBuilder,
    super.defaultLocale,
    final Future<void> Function(String scheme)? launchSchemeAction,
  }) : _launchSchemeAction = launchSchemeAction;

  /// A builder for the consent screen before opening Snap Store
  final ReviewerFallbackConsentBuilder consentBuilder;
  final Future<void> Function(String scheme)? _launchSchemeAction;

  @override
  Future<bool> onLoad() async => true;

  @override
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {
    final isConsent = await consentBuilder(context, locale ?? defaultLocale);
    if (!isConsent) return;

    final scheme = 'snap://review/$packageName';
    final launchSchemeAction = _launchSchemeAction;
    if (launchSchemeAction != null) {
      await launchSchemeAction(scheme);
      return;
    }
    await launchScheme(scheme);
  }
}
