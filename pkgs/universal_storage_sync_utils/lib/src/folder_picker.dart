import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import 'path_validator.dart';
import 'result.dart';

/// A convenience function that handles the entire process of picking a writable
/// directory.
///
/// This function will:
/// 1. Check if folder picking is supported on the current platform.
/// 2. Request necessary permissions on mobile if applicable (though currently unsupported).
/// 3. Show the folder picker to the user.
/// 4. Validate that the selected path is a writable directory.
///
/// It returns a [PickResult] which can be one of [PickSuccess],
/// [PickFailure], or [PickCancelled].
Future<PickResult> pickWritableDirectory({
  BuildContext? context,
  String? initialDirectory,
}) async {
  // 1. Check for platform support first.
  // getDirectoryPath is not supported on iOS or Android.
  if (Platform.isIOS || Platform.isAndroid) {
    return PickFailure(FailureReason.platformNotSupported);
  }

  // 2. Request permissions if needed (primarily for potential future mobile support).
  // On desktop, this is generally not required for the picker itself, but
  // good practice if the app needs broader file access.
  if (Platform.isAndroid || Platform.isIOS) {
    final status = await Permission.storage.request();
    if (status.isDenied) {
      return PickFailure(FailureReason.permissionDenied);
    }
  }

  // 3. Show the folder picker.
  final path = await getDirectoryPath(initialDirectory: initialDirectory);

  if (path == null) {
    // User cancelled the picker.
    return PickCancelled();
  }

  // 4. Validate writability.
  final isWritable = await PathValidator.isWritable(path);
  if (!isWritable) {
    return PickFailure(FailureReason.pathNotWritable);
  }

  return PickSuccess(path);
}
