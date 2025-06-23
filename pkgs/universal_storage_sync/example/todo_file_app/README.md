# Todo App - Universal Storage Sync Demo

A Flutter macOS demo application showcasing the `universal_storage_sync` package's FileSystem provider. This app demonstrates how to build a file-based todo application where each todo is stored as a separate YAML file in a user-selected workspace folder.

## Features

- **VS Code-style folder picker** with persistent folder selection
- **CRUD operations** on todos with YAML file storage
- **Provider/ChangeNotifier** state management
- **Type-safe models** using Dart 3.3+ extension types
- **Error handling** for read-only directories and permission issues
- **Modern Material 3 UI** with responsive design

## Requirements

- **Flutter 3.32+** and **Dart 3.3+** (for extension types support)
- **macOS** development environment
- Proper **entitlements** for file system access

## Getting Started

### 1. Install Dependencies

```bash
cd pkgs/universal_storage_sync/example/todo_app
flutter pub get
```

### 2. macOS Entitlements

The app is pre-configured with the necessary macOS entitlements in `macos/Runner/DebugProfile.entitlements`:

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

### 3. Build and Run

```bash
flutter run -d macos
```

## Usage

### Initial Setup

1. **Launch the app** - you'll see the folder picker screen
2. **Select a workspace folder** using the "Select Folder" button
3. **Start creating todos** - the app will remember your folder selection

### Creating Todos

1. Click the **+ (Add)** button
2. Enter a **title** (required)
3. Optionally add a **description** and **tags**
4. Click **Create**

### Managing Todos

- **Toggle completion** by clicking the checkbox
- **Edit todos** using the menu button (⋮) → Edit
- **Delete todos** using the menu button (⋮) → Delete
- **Refresh** the list using the refresh button in the app bar

### File Structure

Todos are stored in your selected workspace folder:

```
<workspace>/
├── todos/
│   ├── e3b1c0d9-4e5f-6789-abcd-1234567890ab.yaml
│   ├── f4c2d1e0-5f6a-789b-cdef-234567890abc.yaml
│   └── ...
```

### YAML Format

Each todo is stored as a YAML file with this structure:

```yaml
id: e3b1c0d9-4e5f-6789-abcd-1234567890ab
title: "Buy groceries"
description: "2L oat milk, bread, apples"
isCompleted: false
createdAt: 2023-12-25T10:30:00.000Z
completedAt: null
tags:
  - shopping
  - grocery
```

## Architecture

### State Management

The app uses **Provider/ChangeNotifier** for state management:

- `AppState` - Main application state
- Reactive UI updates on state changes
- Error handling with user feedback

### Type-Safe Models

Uses Dart 3.3+ **extension types** for zero-cost type safety:

```dart
extension type const TodoId(String value)
extension type const Todo(Map<String, dynamic> value)
```

### FileSystem Integration

Demonstrates the **FileSystemConfig.builder()** API from Stage 5:

```dart
final config = FileSystemConfig.builder()
    .basePath(workspacePath!)
    .build();

_storageService = StorageService(FileSystemStorageProvider());
await _storageService!.initialize(config.toMap());
```

## Testing

### Unit Tests

```bash
flutter test test/models/todo_test.dart
```

### Widget Tests

```bash
flutter test test/widgets/
```

### Integration Tests

```bash
flutter test integration_test/
```

## Error Handling

The app handles various error scenarios:

- **Directory not found** - Clear error message with retry option
- **Permission denied** - Explanatory dialog with suggestions
- **Read-only directories** - Warning with folder change option
- **Large directories** - Soft limit warnings for performance

## Limitations

- **FileSystem provider only** - No Git or remote sync features
- **macOS only** - Designed specifically for macOS desktop
- **Single workspace** - One active workspace at a time
- **No file watching** - Manual refresh required for external changes

## Performance Considerations

- Each todo is a separate file for simplicity
- YAML parsing on every load
- No caching or lazy loading implemented
- Consider file count limits for large workspaces

## Development

### Project Structure

```
lib/
├── models/
│   └── todo.dart           # Todo and TodoId models
├── pages/
│   ├── folder_picker_page.dart
│   └── todo_list_page.dart
├── state/
│   └── app_state.dart      # Main application state
├── widgets/
│   ├── status_bar.dart
│   └── todo_editor_dialog.dart
└── main.dart
```

### Adding Features

To extend the app:

1. **Add new todo fields** in the `Todo` model
2. **Update YAML serialization** in `AppState._todoToYaml()`
3. **Modify the editor dialog** for new fields
4. **Update tests** accordingly

## Troubleshooting

### App won't start

- Verify Flutter/Dart versions meet requirements
- Check macOS entitlements are correctly configured

### Can't select folder

- Ensure the app has necessary permissions
- Try running from Xcode for detailed permission logs

### Todos don't persist

- Check folder write permissions
- Verify the selected folder exists and is accessible

### Performance issues

- Consider the number of todo files in the workspace
- Large folders (>1000 files) may impact performance

## Links

- [Universal Storage Sync Documentation](../../README.md)
- [Stage 5 Structured Config](../../stage_5.md)
- [FileSystem Provider Details](../../lib/src/providers/filesystem_storage_provider.dart)
