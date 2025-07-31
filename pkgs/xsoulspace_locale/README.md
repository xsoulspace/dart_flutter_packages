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
LocalizationConfig.initialize(LocalizationConfig(
  supportedLanguages: [
    UiLanguage('en', 'English'),
    UiLanguage('es', 'Spanish'),
    UiLanguage('fr', 'French'),
  ],
  fallbackLanguage: UiLanguage('en', 'English'),
));
```

### 2. Locale Logic Flow

```dart
// 1. Initialize logic and resource
final logic = LocaleLogic();
final resource = await logic.initUiLocaleResource();

// 2. Use resource for reactive UI
ValueListenableBuilder<Locale>(
  valueListenable: resource,
  builder: (context, locale, child) => Text(locale.languageCode),
)

// 3. Update locale at runtime
final result = await logic.updateLocale(
  newLocale: Locale('es'),
  oldLocale: currentLocale,
  uiLocale: currentUiLocale,
  onLocaleChanged: (locale) => S.delegate.load(locale),
);
```

## Key Classes

### LocaleLogic

- **Purpose**: Core locale management operations
- **Key Methods**:
  - `initUiLocaleResource()` - Initialize with system locale
  - `updateLocale()` - Runtime locale changes with Intl reload
- **AI Usage**: Always call init first, then use update for changes

### UiLocaleResource

- **Purpose**: Reactive locale state container
- **Usage**: Use with ValueListenableBuilder for UI updates
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
  UiLanguage('en', 'English'): 'Hello',
  UiLanguage('es', 'Spanish'): 'Hola',
});

// Get value for current locale
final greeting = localized.getValue(resource.value);

// Get value for specific language
final spanishGreeting = localized.getValueByLanguage(
  UiLanguage.byCode('es')
);
```

## AI Agent Guidelines

1. **Always initialize LocalizationConfig first**
2. **Use LocaleLogic for all locale operations**
3. **UiLocaleResource is always valid for display**
4. **Provide onLocaleChanged callback for Intl reload**
5. **Use LocalizedMap for multi-language content**
6. **Check return values from updateLocale for changes**

## Architecture

```
LocalizationConfig (singleton)
    ↓ configures
LocaleLogic (operations)
    ↓ creates/updates
UiLocaleResource (reactive state)
    ↓ used by
UI Components (ValueListenableBuilder)
```

The package provides a complete locale management solution with reactive UI support, Intl integration, and type-safe multi-language content handling.
