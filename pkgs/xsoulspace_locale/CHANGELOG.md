# Changelog

## 0.3.5

- LocalizedMap now is class instead of extension type.
- added: `copyRawWith` method to `LocalizedMap` for immutable updates to localized content.

## 0.3.4

- fix: LocalizedMap now Map<String, String> instead of Map<UiLanguage, String> - this improves JSON serialization and deserialization.

## 0.3.3

- chore: xsoulspace_foundation 0.3.0

## 0.3.2

- chore: from_json_to_json 0.3.0
- chore: xsoulspace_lints 0.1.2

## 0.3.1

- fix: conditional export from web to js_interop

## 0.3.0

BREAKING:

- New setup:

```dart
const languages = (
  en: UiLanguage('en', 'English'),
  es: UiLanguage('es', 'Spanish'),
  fr: UiLanguage('fr', 'French'),
);
const supportedLanguages = [
  languages.en,
  languages.es,
  languages.fr,
];

const localeLogic = LocaleLogic();

final uiLocaleResource = await localeLogic.createUiLocaleResource();

LocalizationConfig.initialize(LocalizationConfig(
  supportedLanguages: supportedLanguages,
  fallbackLanguage: uiLocaleResource.value.language,
));

localeLogic.initUiLocaleResource(uiLocaleResource: uiLocaleResource);
```

- Changed:

UiLocaleNotifier is now UiLocaleResource.

- chore: Improved package documentation for better AI agent comprehension
  - Enhanced dartdoc comments with @ai annotations for AI-specific guidance
  - Added comprehensive usage examples and code snippets
  - Updated README with clear initialization patterns and provider integration
  - Improved API documentation with practical implementation examples
  - Added architecture diagrams and AI agent guidelines

## 0.2.0

- Stable release.

## 0.0.1

- Initial release.
