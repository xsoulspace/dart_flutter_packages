// ignore_for_file: invalid_annotation_target, avoid_annotating_with_dynamic
part of 'localization.dart';

/// User-friendly locale representation for language selection UI.
///
/// Pairs a display name with a Flutter locale for user interface.
///
/// ```dart
/// final namedLocale = NamedLocale(
///   name: 'English',
///   locale: Locale('en'),
/// );
/// ```
///
/// @ai Use for language selection dropdowns and UI components. The [name]
/// should be localized and user-friendly.
@immutable
class NamedLocale extends Equatable {
  /// Creates a named locale with display name and Flutter locale.
  const NamedLocale({required this.name, required this.locale});

  /// User-friendly display name for the locale.
  final String name;

  /// Flutter locale used for localization.
  final Locale locale;

  /// Language code extracted from the locale.
  ///
  /// @ai Convenient access to language code without accessing locale directly.
  String get code => locale.languageCode;

  @override
  List<Object?> get props => [name, locale];

  @override
  String toString() => 'NamedLocale(name: $name, locale: $locale)';
}

/// Converts language code string to Flutter locale.
///
/// @ai Returns null for invalid/empty codes. Use for safe locale creation.
Locale? localeFromString(final String? languageCode) {
  if (languageCode == null || languageCode.isEmpty) return null;
  return UiLanguage.byCode(languageCode)?.locale;
}

/// Converts Flutter locale to language code string.
///
/// @ai Returns null for null locales. Use for serialization.
String? localeToString(final Locale? locale) => locale?.languageCode;

/// Converts dynamic map to localized value map.
///
/// Handles both string and map inputs for flexible JSON parsing.
///
/// @ai Use for parsing localized content from JSON. Throws for
/// unsupported types.
LocalizedMap localeValueFromMap(final dynamic map) {
  if (map case String _) {
    return LocalizedMap.fromLanguages();
  } else if (map case final Map map) {
    if (map.isEmpty) {
      return LocalizedMap.fromLanguages();
    }
    final localeMap = <UiLanguage, String>{};
    for (final key in map.keys) {
      final language = UiLanguage.byCode(key);
      if (language == null) continue;
      localeMap[language] = map[key];
    }
    return LocalizedMap(localeMap);
  } else {
    throw UnimplementedError('localeValueFromMap $map');
  }
}

/// Converts localized map to string map for JSON serialization.
///
/// @ai Use for saving localized content to JSON format.
Map<String, String> localeValueToMap(final Map<UiLanguage, String> locales) =>
    locales.map((final key, final value) => MapEntry(key.code, value));

/// Type-safe container for localized string values.
///
// ignore: unintended_html_in_doc_comment
/// Provides zero-overhead wrapper around Map<UiLanguage, String> with
/// JSON serialization and convenient access methods.
///
/// ```dart
/// final localized = LocalizedMap({
///   languages.en: 'Hello',
///   languages.es: 'Hola',
/// });
/// final greeting = localized.getValue(Locale('en')); // 'Hello'
/// ```
///
/// @ai Use for managing multi-language content. Provides fallback to default
/// language when requested language is not available.
extension type const LocalizedMap(Map<UiLanguage, String> value) {
  /// Creates from JSON with flexible input format.
  ///
  /// @ai Handles both direct maps and wrapped maps with 'value' key.
  factory LocalizedMap.fromJson(final dynamic json) {
    if (json case {'value': final dynamic value}) {
      return LocalizedMap(jsonDecodeMapAs(value));
    } else {
      return LocalizedMap(jsonDecodeMapAs(json));
    }
  }

  /// Creates empty map with all supported languages.
  ///
  /// @ai Use for initializing localized content with empty strings.
  factory LocalizedMap.fromLanguages() => LocalizedMap({
    for (final lang in LocalizationConfig.instance.supportedLanguages) lang: '',
  });

  /// Converts to JSON with 'value' wrapper.
  ///
  /// @ai Use for consistent JSON serialization format.
  static Map<String, dynamic> toJsonValueMap(final LocalizedMap map) => {
    'value': localeValueToMap(map.value),
  };

  /// Converts to JSON map without wrapper.
  Map<String, dynamic> toJson() => localeValueToMap(value);

  /// Empty localized map.
  static const empty = LocalizedMap({});

  /// Gets localized value for Flutter locale.
  ///
  /// @ai Converts locale to language and retrieves value with fallback.
  String getValue(final Locale locale) =>
      getValueByLanguage(UiLanguage.byLocale(locale));

  /// Gets localized value for specific language.
  ///
  /// @ai Falls back to default language if requested language not found.
  String getValueByLanguage([final UiLanguage? language]) {
    final lang = language ?? getCurrentLanguage();
    return value[lang] ??
        value[LocalizationConfig.instance.fallbackLanguage] ??
        '';
  }

  /// Gets current language from Intl locale.
  ///
  /// @ai Extracts language code from current Intl locale with fallback.
  static UiLanguage getCurrentLanguage() {
    final languageCode = getLanguageCodeByStr(Intl.getCurrentLocale());
    return UiLanguage.byCodeWithFallback(languageCode);
  }

  /// Creates copy with optional value replacement.
  ///
  /// @ai Use for immutable updates to localized content.
  LocalizedMap copyWith({final Map<UiLanguage, String>? value}) =>
      LocalizedMap(value ?? this.value);
}
