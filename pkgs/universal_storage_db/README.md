# Universal Storage DB

Note: this package is still in early development and the API is quite possible will change rapidly in future.

# Why yet another database?

[Short video demo](https://youtu.be/eykzsmgMBv8?si=qjoM7dbcj7FNSsYx)

The idea is simple - I want to make it easy to access & manage underlying storage system (file system, git, cloud) in a type-safe way with simplest API possible and take into account case if the this idea fails.

Imagine case if you developing the app or game and suddenly, developer who maintained the db deprecates it.

In such cases having a db that stores data in a way that is easy to migrate to another system, or just parse the data easy with any tools available and also that means end user will be able to parse any saved files with LLMs which already know how to parse this json or yaml.

So the data will not be lost, at least this way.

My target is to reach stability of xls files of MS Excel, which are can be opened and modified even after 10 years passed.

This package is built on top of `universal_storage_sync`, providing access to:

- **File System Storage**: Local file system operations
<!-- - **Git Integration**: Version control and synchronization
- **Cloud Storage**: Future support for cloud providers -->
- **Cross-Platform**: Consistent API across all platforms (not tested, web in WIP)

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  universal_storage_db: ^0.1.0-dev.1
```

## Quick Start

```dart
import 'package:universal_storage_db/universal_storage_db.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

// Initialize the "database"
final db = UniversalStorageDb(
  storageConfig: FileSystemConfig(
    filePathConfig: FilePathConfig(
      path: '/path/to/storage',
    ),
  ),
  config: const UniversalStorageDbConfig(),
);

await db.init();

// Store and retrieve data
await db.setBool(key: 'darkMode', value: true);
final isDark = await db.getBool(key: 'darkMode');

await db.setString(key: 'username', value: 'john_doe');
final username = await db.getString(key: 'username');

await db.setMap(key: 'userProfile', value: {
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
});
final profile = await db.getMap('userProfile');
```

## Configuration

### Storage Router Types

Control how different data types are organized across files:

```dart
const config = UniversalStorageDbConfig(
  storageRouterTypes: StorageRouterType(
    placeBoolsToOneFile: true,      // All bools in one file
    placeIntsToOneFile: false,     // Each int in separate file
    placeStringsToOneFile: true,   // All strings in one file
    placeSingleMapToOneFile: true, // All maps in one file
    placeMapListInSingleFile: false, // Each map list in separate file
  ),
);
```

### Custom File Naming

Define custom file naming strategies:

```dart
const config = UniversalStorageDbConfig(
  boolSingleFileNameBuilder: (key) => 'settings_$key',
  stringSeparateFileNameBuilder: (key) => 'data_$key.json',
  mapSingleFileNameBuilder: (key) => 'profiles_$key',
);
```

### Default File Names

The package uses these default file naming conventions:

- **Bools**: `xsun_b` (single) / `xsun_b_$key` (separate)
- **Ints**: `xsun_i` (single) / `xsun_i_$key` (separate)
- **Strings**: `xsun_s` (single) / `xsun_s_$key` (separate)
- **Maps**: `xsun_m` (single) / `xsun_m_$key` (separate)
- **Map Lists**: `xsun_ml` (single) / `xsun_ml_$key` (separate)

## API Reference

### Basic Operations

#### Boolean Operations

```dart
// Store a boolean value
await db.setBool(key: 'isFirstLaunch', value: true);

// Retrieve a boolean value
final isFirstLaunch = await db.getBool(key: 'isFirstLaunch', defaultValue: false);
```

#### Integer Operations

```dart
// Store an integer value
await db.setInt(key: 'userScore', value: 1250);

// Retrieve an integer value
final score = await db.getInt(key: 'userScore', defaultValue: 0);
```

#### String Operations

```dart
// Store a string value
await db.setString(key: 'userToken', value: 'abc123xyz');

// Retrieve a string value
final token = await db.getString(key: 'userToken', defaultValue: '');
```

#### Map Operations

```dart
// Store a map
await db.setMap(key: 'userSettings', value: {
  'theme': 'dark',
  'notifications': true,
  'language': 'en',
});

// Retrieve a map
final settings = await db.getMap('userSettings');
```

### Advanced Operations

#### Generic Item Storage

```dart
class User {
  final String name;
  final int age;

  User({required this.name, required this.age});

  Map<String, dynamic> toJson() => {'name': name, 'age': age};
  static User? fromJson(Map<String, dynamic> json) =>
    User(name: json['name'], age: json['age']);
}

// Store a custom object
await db.setItem<User>(
  key: 'currentUser',
  value: User(name: 'John', age: 30),
  toJson: (user) => user.toJson(),
);

// Retrieve a custom object
final user = await db.getItem<User>(
  key: 'currentUser',
  fromJson: User.fromJson,
  defaultValue: User(name: 'Guest', age: 0),
);
```

#### List Operations

```dart
// Store a list of maps
await db.setMapList(key: 'userHistory', value: [
  {'action': 'login', 'timestamp': DateTime.now().millisecondsSinceEpoch},
  {'action': 'logout', 'timestamp': DateTime.now().millisecondsSinceEpoch},
]);

// Retrieve a list of maps
final history = await db.getMapIterable(key: 'userHistory');

// Store a list of strings
await db.setStringList(key: 'favoriteColors', value: ['blue', 'green', 'red']);

// Retrieve a list of strings
final colors = await db.getStringsIterable(key: 'favoriteColors');

// Store a list of custom objects
await db.setItemsList<User>(
  key: 'users',
  value: [User(name: 'John', age: 30), User(name: 'Jane', age: 25)],
  toJson: (user) => user.toJson(),
);

// Retrieve a list of custom objects
final users = await db.getItemsIterable<User>(
  key: 'users',
  fromJson: User.fromJson,
);
```

## Performance Considerations

### Caching Strategy

The database implements intelligent caching for optimal performance:

- **Single File Mode**: Data is cached in memory for instant access
- **Separate File Mode**: Each key-value pair is stored in its own file if needed by configuration
- **Automatic Cache Management**: Cache is automatically updated on writes

### File Organization

Choose your file organization strategy based on your use case:

- **Single File**: Better for small datasets with frequent access
- **Separate Files**: Better for large datasets or when you need granular control

## Error Handling (not implemented yet)

Currently there is no error handling implemented, so all errors will be thrown.

```dart
try {
  await db.setString(key: 'data', value: 'important data');
} catch (e) {
  // Handle storage errors
  print('Storage error: $e');
}
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- [GitHub Repository](https://github.com/xsoulspace/universal_storage_db)
- [Issue Tracker](https://github.com/xsoulspace/universal_storage_db/issues)
- [Documentation](https://github.com/xsoulspace/universal_storage_db/tree/main/pkgs/universal_storage_db)
