// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl_standalone.dart'
    if (dart.library.web) 'package:intl/intl_browser.dart';

import 'localization.dart';

/// {@template locale_logic}
/// Core locale management logic for Flutter applications.
///
/// Handles system locale detection, locale updates, and Intl integration.
/// Provides two key operations: initialization and locale updates.
///
/// ```dart
/// final logic = LocaleLogic();
/// final resource = await logic.initUiLocaleResource();
/// ```
///
/// @ai Use this class to manage locale state. Always call [initUiLocaleResource]
/// first, then use [updateLocale] for runtime changes. The returned resource
/// should be used with ValueListenableBuilder for UI updates.
/// {@endtemplate}
@immutable
class LocaleLogic {
  /// {@macro locale_logic}
  const LocaleLogic();

  /// Returns the current system locale as detected by the platform.
  ///
  /// Note: The returned locale may not be included in the application's
  /// supported locales.
  ///
  /// @ai Use this to get the system locale.
  Future<Locale> get _systemLocale async {
    final systemLocaleStr = await findSystemLocale();
    return Locale.fromSubtags(languageCode: systemLocaleStr.substring(0, 2));
  }

  /// Detects system locale and validates against supported locales.
  ///
  /// Should be called only after [LocalizationConfig] is initialized.
  ///
  /// @ai Use this to system locale if supported, otherwise fallback locale.
  Future<Locale> get _defaultLocale async {
    final systemLocale = await _systemLocale;
    final isSupported = LocalizationConfig.instance.supportedLocales.contains(
      systemLocale,
    );
    if (isSupported) return systemLocale;
    return Locales.fallback;
  }

  /// Creates initial locale resource with system locale.
  ///
  /// @ai Call this once during app initialization. Returns a [UiLocaleResource]
  /// that can be used with ValueListenableBuilder for reactive UI updates.
  Future<UiLocaleResource> createUiLocaleResource() async =>
      UiLocaleResource(await _systemLocale);

  /// Initializes [UiLocaleResource] with default and supported locale.
  ///
  /// @ai Call this once during app initialization.
  Future<void> initUiLocaleResource({
    required final UiLocaleResource uiLocaleResource,
  }) async {
    final defaultLocale = await _defaultLocale;
    uiLocaleResource.value = defaultLocale;
  }

  /// Updates application locale and triggers Intl reload.
  ///
  /// Returns null if no change occurred. Otherwise returns updated locale values.
  ///
  /// Key concepts:
  /// - [updatedLocale]: Saved locale (can be null for system default)
  /// - [uiLocale]: Display locale (always has a value)
  /// - [onLocaleChanged]: Callback to reload Intl (e.g., S.delegate.load(locale))
  ///
  /// ```dart
  /// final result = await logic.updateLocale(
  ///   newLocale: Locale('es'),
  ///   oldLocale: currentLocale,
  ///   uiLocale: currentUiLocale,
  ///   onLocaleChanged: (locale) => S.delegate.load(locale),
  /// );
  /// ```
  ///
  /// @ai Use this for runtime locale changes. Always provide [onLocaleChanged]
  /// to reload Intl resources. Check return value to determine if update occurred.
  Future<({Locale? updatedLocale, Locale uiLocale})?> updateLocale({
    required final Locale? newLocale,
    required final Locale? oldLocale,
    required final Locale uiLocale,
    final ValueChanged<Locale>? onLocaleChanged,
  }) async {
    final didChanged =
        oldLocale?.languageCode != newLocale?.languageCode ||
        uiLocale != newLocale;
    if (!didChanged) return null;

    Locale? updatedLocale = oldLocale;
    Locale updatedUiLocale = uiLocale;
    final defaultLocale = await _defaultLocale;

    if (newLocale == null) {
      onLocaleChanged?.call(defaultLocale);
      updatedLocale = null;
      updatedUiLocale = defaultLocale;
    } else {
      if (!LocalizationConfig.instance.isLocaleSupported(newLocale)) {
        throw UnsupportedError(
          'The requested locale $newLocale is not supported.',
        );
      }

      final localeCandidate = UiLanguage.byLocale(newLocale).locale;

      onLocaleChanged?.call(localeCandidate);
      updatedLocale = localeCandidate;
      updatedUiLocale = localeCandidate;
    }

    return (updatedLocale: updatedLocale, uiLocale: updatedUiLocale);
  }
}
