# xsoulspace_state_utils

A Dart package providing ordered collections and reactive state management utilities for Flutter applications.

## What it does

Solves two key problems:

- **Ordered collections**: Maps and Lists that maintain insertion order with key-based access
- **Reactive state management**: Notifiers for ordered collections that automatically notify listeners of changes

## Installation

```yaml
dependencies:
  xsoulspace_state_utils: ^0.1.0
```

## Quick Start

```dart
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

// Ordered map that maintains insertion order
final orderedMap = MutableOrderedMap<String, User>();
orderedMap.upsert('alice', User(name: 'Alice'));
orderedMap.upsert('bob', User(name: 'Bob'));

// Access by key or iterate in order
print(orderedMap['alice']); // User(name: 'Alice')
print(orderedMap.orderedValues); // [User(Alice), User(Bob)]

// Efficient batch operations
final users = [
  User(id: 'user1', name: 'Alice'),
  User(id: 'user2', name: 'Bob'),
  User(id: 'user3', name: 'Charlie'),
];

// Batch insert multiple users efficiently (single cache invalidation)
orderedMap.upsertAll(users);

// Reactive notifier for state management with efficient batch updates
final userNotifier = OrderedMapNotifier<String, User>();
userNotifier.addListener(() => print('Users changed'));

// Batch update with single notification (prevents excessive UI rebuilds)
userNotifier.upsertAll(users);
```

## Core Components

### Ordered Collections

- **`MutableOrderedMap<K, V>`** - Ordered map with mutable operations
- **`ImmutableOrderedMap<K, V>`** - Immutable ordered map
- **`MutableOrderedList<V>`** - Ordered list with mutable operations
- **`ImmutableOrderedList<V>`** - Immutable ordered list
- **`MutableOrderedSet<V>`** - Ordered set with mutable operations
- **`ImmutableOrderedSet<V>`** - Immutable ordered set

### State Notifiers

- **`OrderedMapNotifier<K, V>`** - Reactive ordered map notifier
- **`OrderedListNotifier<V>`** - Reactive ordered list notifier

Both extend Flutter's `ChangeNotifier` for automatic UI updates.

### Experimental

- **`Chain<TStartWith, TThenResult>`** - Type-safe command pipeline pattern (may be removed)

## Agentic Executable (AE) Usage Patterns:

TODO: migrate to [Agentic Executable (AE)](https://github.com/fluent-meaning-symbiotic/agentic_executables).

Rules are in `ai_use` folder.

- `command_resource_pattern.mdc` - Command-Resource Pattern

## License

MIT License. See [LICENSE](LICENSE) for details.
