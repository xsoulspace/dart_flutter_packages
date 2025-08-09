<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

The `universal_storage_sync_utils` package provides a set of Flutter UI helpers and platform-specific utilities designed to work with the `universal_storage_sync` package. It simplifies common tasks related to file storage and version control integration in a Flutter application.

## Features

- **Cross-Platform Writable Directory Picker**: A high-level function `pickWritableDirectory` that allows users to select a folder, validates write permissions, and handles platform-specific requirements.
- **macOS Security-Scoped Bookmarks**: Automatically creates and manages security-scoped bookmarks on macOS to ensure persistent access to user-selected directories, complying with App Sandbox restrictions.
- **High-Level Repository Management**: The `RepositoryManager` class provides a UI-agnostic way to handle the workflow of selecting an existing or creating a new remote repository (e.g., on GitHub). It uses a delegate pattern (`RepositorySelectionUIDelegate`) so you can implement your own UI.
- **Helper Utilities**: Includes path validators and robust `Result` types for cleaner, type-safe error handling.

## Getting started

This package is designed to be used with `universal_storage_sync` in a Flutter application.

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  universal_storage_sync_utils: ^0.1.0-dev.3
```

## Usage

Here's a quick example of how to use the `pickWritableDirectory` function:

```dart
import 'package:flutter/material.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

class MyFolderPickerWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final result = await pickWritableDirectory();
        switch (result) {
          case PickSuccess(path: final path):
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Selected folder: $path')),
            );
            // You can now store the path and the macOSBookmark (if on macOS)
            // final bookmark = result.macOSBookmark;
            break;
          case PickFailure(reason: final reason):
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to pick folder: $reason')),
            );
            break;
          case PickCancelled():
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('User cancelled')),
            );
            break;
        }
      },
      child: Text('Pick a Folder'),
    );
  }
}
```

For more advanced examples, such as using the `RepositoryManager`, please see the `/example` folder.

## Additional information

This package is part of the `universal_storage_sync` monorepo. For more information, to file issues, or to contribute, please visit the main repository.
