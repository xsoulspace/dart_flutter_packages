import 'package:flutter/material.dart';

import 'locale_logic.dart';

/// A class that holds the locale resource for the application.
///
/// Use [LocaleLogic.initLocaleResource] to initialize the locale resource.
///
/// Use [LocaleLogic.updateLocale] to update the locale resource.
///
/// Always have value, as we need something to show to the user.
class UiLocaleResource extends ValueNotifier<Locale> {
  UiLocaleResource(super.value);
}
