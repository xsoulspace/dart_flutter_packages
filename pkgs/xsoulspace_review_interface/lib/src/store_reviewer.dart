import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:url_launcher/url_launcher.dart';

/// A function type for building a fallback consent screen.
///
/// This function takes a [BuildContext] and [Locale] and returns a
/// [Future<bool>]
/// indicating whether the user has given consent.
///
/// @ai Use this type when implementing custom consent screens for store
/// reviews.
typedef ReviewerFallbackConsentBuilder =
    Future<bool> Function(BuildContext context, Locale locale);

/// {@template store_reviewer}
/// Base class for implementing store review functionality.
///
/// This class provides a common interface for different store review
/// implementations.
///
/// @ai When extending this class, ensure to override [requestReview] method.
/// {@endtemplate}
base class StoreReviewer {
  /// {@macro store_reviewer}
  const StoreReviewer({
    this.defaultLocale = const Locale('en'),
    this.packageName = '',
  });

  /// Default locale for localized content
  final Locale defaultLocale;

  /// Package name for store-specific operations
  final String packageName;

  /// Initializes the reviewer.
  ///
  /// Override this method to perform any necessary setup.
  ///
  /// @ai Implement this method for any initialization logic specific to the
  /// reviewer.
  Future<bool> onLoad() async => false;

  /// Requests a review from the user.
  ///
  /// This method must be overridden in subclasses to implement
  /// platform-specific review requests.
  ///
  /// @ai Ensure to implement this method with the appropriate store review
  /// logic.
  @mustBeOverridden
  Future<void> requestReview(
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {}

  /// Launches a scheme.
  ///
  /// This method is used to launch a scheme in the app.
  ///
  /// @ai Use this method to launch a scheme in the app.
  Future<void> launchScheme(final String scheme) async {
    if (await canLaunchUrl(Uri.parse(scheme))) {
      await launchUrl(Uri.parse(scheme));
    }
  }
}
