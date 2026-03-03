# xsoulspace_state_utils

Ordered collection data structures and reactive notifiers for Flutter state management.

## Features

- Ordered map/list/set collections with predictable iteration order
- Mutable and immutable collection variants
- `ChangeNotifier` wrappers for reactive UI updates
- Efficient batch operations (`upsertAll`, `assignAllOrdered`)

## Installation

```yaml
dependencies:
  xsoulspace_state_utils: ^0.6.0
```

## Quick start

```dart
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

final users = OrderedMapNotifier<String, User>(toKey: (u) => u.id);
users.addListener(() {
  // Trigger UI update or side effects.
});

users.upsertAll([
  User(id: 'u1', name: 'Alice'),
  User(id: 'u2', name: 'Bob'),
]);

final ordered = users.orderedValues;
```

## Main APIs

- `MutableOrderedMap<K, V>` / `ImmutableOrderedMap<K, V>`
- `MutableOrderedList<V>` / `ImmutableOrderedList<V>`
- `MutableOrderedSet<V>` / `ImmutableOrderedSet<V>`
- `OrderedMapNotifier<K, V>` and `OrderedListNotifier<V>`

## License

MIT (see [LICENSE](LICENSE)).
