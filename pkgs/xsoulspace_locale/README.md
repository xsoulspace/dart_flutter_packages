# xsoulspace_locale

I've developed this package as I've tried to simplify work with localizations.
The most complicated problem with all packages - it is easy to create strings and translations, but quite hard to manage them.

To fix this problem this package uses LocalizedMap which utilizes current
locale to get the string.
Also added boilerplate for keyboard languages and languages changes.

## Core Concepts

### 1. Configuration First

Initialize supported languages before any locale operations:

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

### 2. Locale Logic Flow

```dart
// 1. Create and initialize resource
const logic = LocaleLogic();
final resource = await logic.createUiLocaleResource();

// 2. Use resource for reactive UI
ValueListenableBuilder<Locale>(
  valueListenable: resource,
  builder: (context, locale, child) => Text(locale.languageCode),
)
```

or with provider:

````dart
// 2.1. Use resource for reactive UI with provider
final locale = context.watch<UiLocaleResource>().value;

```dart
// 2.2. Create a hook
Locale useLocale() => context.watch<UiLocaleResource>().value;
```

```dart
// 3. Update locale at runtime
final result = await logic.updateLocale(
  newLocale: newLocale,
  oldLocale: currentLocale,
  uiLocale: uiLocaleResource.value,
  onLocaleChanged: (locale) => S.delegate.load(locale),
);
```

## Key Classes

### LocaleLogic

- **Purpose**: Core locale management operations
- **Key Methods**:
  - `createUiLocaleResource()` - Create resource with system locale
  - `initUiLocaleResource()` - Initialize with validated locale
  - `updateLocale()` - Runtime locale changes with Intl reload
- **AI Usage**: Create resource first, then initialize with config

### UiLocaleResource

- **Purpose**: Reactive locale state container
- **Usage**: Use with ValueListenableBuilder or context.watch for UI updates
- **AI Usage**: Always contains valid locale, ready for display

### LocalizationConfig

- **Purpose**: Global configuration singleton
- **AI Usage**: Must be initialized before any locale operations

### UiLanguage

- **Purpose**: Core language entity with code and display name
- **AI Usage**: Use for language identification and conversion

### LocalizedMap

- **Purpose**: Type-safe multi-language content container
- **AI Usage**: Use for managing localized strings with fallback support

## Common Patterns

### Language Selection UI

```dart
final namedLocales = namedLocalesMap.values.toList();
DropdownButton<NamedLocale>(
  items: namedLocales.map((nl) =>
    DropdownMenuItem(value: nl, child: Text(nl.name))
  ).toList(),
  onChanged: (selected) {
    if (selected != null) {
      logic.updateLocale(
        newLocale: selected.locale,
        oldLocale: resource.value,
        uiLocale: resource.value,
        onLocaleChanged: (locale) => S.delegate.load(locale),
      );
    }
  },
)
```

### Localized Content Management

```dart
final localized = LocalizedMap({
  languages.en: 'Hello',
  languages.es: 'Hola',
});

// Get value for current locale
final greeting = localized.getValue(resource.value);

// Get value for specific language
final spanishGreeting = localized.getValueByLanguage(
  UiLanguage.byCode('es')
);
```

### Provider Integration

```dart
// With provider pattern
final locale = context.watch<UiLocaleResource>().value;

// Or create a custom hook
Locale useLocale() => context.watch<UiLocaleResource>().value;
```

## AI Agent Guidelines

1. **Always initialize LocalizationConfig first with createUiLocaleResource**
2. **Use LocaleLogic.createUiLocaleResource() then initUiLocaleResource()**
3. **UiLocaleResource is always valid for display**
4. **Provide onLocaleChanged callback for Intl reload**
5. **Use LocalizedMap for multi-language content**
6. **Check return values from updateLocale for changes**
7. **Use const for language definitions to improve performance**

## Architecture

```
LocalizationConfig (singleton)
    ↓ configures
LocaleLogic (operations)
    ↓ creates/updates
UiLocaleResource (reactive state)
    ↓ used by
UI Components (ValueListenableBuilder/Provider)
```

The package provides a complete locale management solution with reactive UI support, Intl integration, and type-safe multi-language content handling.
````
