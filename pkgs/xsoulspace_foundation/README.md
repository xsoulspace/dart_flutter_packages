# xsoulspace_foundation

This package is a collection of useful utilities, extensions, and helpers that I often use in my projects. It is intended
for personal and commercial projects, providing reusable components that enhance productivity and maintainability.
Please note: this package is kinda stable, but some parts may be unstable (I've marked them with unstable tag) or lacks
documentation.

## Install

```yaml
dependencies:
  xsoulspace_foundation: ^0.3.0
```

```dart
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
```

---

## API at a glance

### Annotations (design hints)

| Name                                     | Use                                         |
| ---------------------------------------- | ------------------------------------------- |
| `@stateless` / `Stateless`               | Class has no exposed state (e.g. command).  |
| `@resource` / `Resource`                 | Class holds state, no business logic.       |
| `@heavyComputation` / `HeavyComputation` | Function does heavy work; consider isolate. |

### Interfaces

- **`Disposable`** — `void dispose()` for cleanup.
- **`Loadable`** — `Future<void> onLoad()` for async init.

### Models (freezed)

- **`LoadableContainer<T>`** — `value` + `isLoaded`; `.loaded(value)`, `.isLoading`.
- **`FieldContainer<T>`** — `value` + `errorText` + `isLoading` (forms).

### Extensions

- **String** — `toColor()`, `isUrl`, etc.
- **Iterable** — `toIndexedMap(toId)`, async convertors.
- **List / Map / Set / num / DateTime** — see `lib/src/extensions/`.

### Utils

| Util                 | Purpose                              |
| -------------------- | ------------------------------------ |
| `IdCreator.create()` | v1 UUID string.                      |
| `dateTimeNowUtc()`   | `DateTime.now().toUtc()`.            |
| `Randomizer()`       | `nextInt(min:, max:)`, `nextBool()`. |

### Local DB (`LocalDbI` + `PrefsDb`)

Key-value persistence (SharedPreferences-backed). Call `init()` before use.

```dart
final db = PrefsDb();
await db.init();

await db.setString(key: 'k', value: 'v');
final s = await db.getString(key: 'k'); // '' if missing

await db.setMap(key: 'm', value: {'a': 1});
final m = await db.getMap('m');

await db.setBool(key: 'b', value: true);
await db.setInt(key: 'i', value: 42);
// getBool(key:, defaultValue: false), getInt(key:, defaultValue: 0)

await db.setItem(key: 'item', value: obj, toJson: (e) => e.toJson());
final obj = await db.getItem(key: 'item', fromJson: My.fromJson, defaultValue: fallback);

await db.setStringList(key: 'list', value: ['a','b']);
final list = await db.getStringsIterable(key: 'list');
// setMapList / getMapIterable, setItemsList / getItemsIterable

await db.clearKey(key: 'k');
await db.clear();
```

---

## License

This package is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.
