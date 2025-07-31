import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl_standalone.dart'
    if (dart.library.web) 'package:intl/intl_browser.dart';

import 'localization.dart';

/// Stateless class that holds the locale logic for the application.
///
/// Use [LocaleLogic.initUiLocaleResource] to initialize the ui locale resource.
@immutable
class LocaleLogic {
  const LocaleLogic();
  Future<Locale> get _defaultLocale async {
    final systemLocaleStr = await findSystemLocale();

    final systemLocale = Locale.fromSubtags(
      languageCode: systemLocaleStr.substring(0, 2),
    );
    final isSupported = LocalizationConfig.instance.supportedLocales.contains(
      systemLocale,
    );
    if (isSupported) return systemLocale;
    return Locales.fallback;
  }

  /// Initialize the locale resource with the default system locale.
  Future<UiLocaleResource> initUiLocaleResource() async {
    final defaultLocale = await _defaultLocale;
    return UiLocaleResource(defaultLocale);
  }

  /// Ui locale will not be saved, and will always be in runtime
  /// updatedLocale is the one that will be saved.
  ///
  /// Use [onLocaleChanged] to update the Intl localization,
  /// for example, S.delegate.load(locale)
  ///
  /// To get [uiLocale] you may use [UiLocaleResource.value]
  ///
  /// Response:
  ///
  /// The difference between [updatedLocale] and [uiLocale] is that
  /// [updatedLocale] is the locale that will be saved and therefore may be
  /// null, and [uiLocale] is the locale that will be shown to the user and
  /// will always have a locale. If saved locale is null, it will have system
  /// locale.
  ///
  /// [updatedLocale] is the locale that will be used to update the Intl
  /// localization, for example, S.delegate.load(locale)
  ///
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
