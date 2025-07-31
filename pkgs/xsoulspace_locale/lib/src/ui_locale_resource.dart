import 'package:flutter/material.dart';

import 'locale_logic.dart';

/// {@template ui_locale_resource}
/// Notifier that wraps a [Locale] value and notifies listeners of changes.
/// Always contains a valid locale for display purposes.
///
/// ```dart
/// final uiLocaleResource = UiLocaleResource(Locale('en'));
/// ```
///
/// for widget with provider:
///
/// ```dart
/// final locale = context.watch<UiLocaleResource>().value;
/// ```
///
/// or add a hook:
///
/// ```dart
/// Locale useLocale() => context.watch<UiLocaleResource>().value;
/// ```
///
/// @ai Use with ValueListenableBuilder for reactive UI. The value is always
/// valid and ready for display. Create via [LocaleLogic.initUiLocaleResource].
/// {@endtemplate}
class UiLocaleResource extends ValueNotifier<Locale> {
  /// {@macro ui_locale_resource}
  ///
  /// @ai The value should always be a valid, supported locale.
  UiLocaleResource(super.value);
}
