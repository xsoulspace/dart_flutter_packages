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

// Reactive notifier for state management
final userNotifier = OrderedMapNotifier<String, User>();
userNotifier.addListener(() => print('Users changed'));
userNotifier.upsert('alice', User(name: 'Alice')); // Triggers listener
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

## AI Agent Usage Patterns:

All patterns are in `lib_ai_use` folder.

- `command_resource_pattern.mdc` - Command-Resource Pattern

## License

MIT License. See [LICENSE](LICENSE) for details.
