# Universal Storage Sync – Utilities Extraction Plan (Revised)

# ============================================================

# FINAL GOAL

# ----------

# Publish a new Flutter package `universal_storage_sync_utils`

# that offers:

# • A robust, cross-platform folder picker (Desktop/Web).

# • Path-writability verification.

# • A clear API for handling permissions and platform limitations.

#

# Key Revisions:

# 1. Package Type: Changed from Dart to Flutter to support BuildContext.

# 2. API Design: Switched to a sealed `PickResult` class instead of a nullable

# string for clearer success/failure handling.

# 3. Platform Support: Clarified that folder picking is unsupported on mobile

# and simplified implementation to rely solely on `file_selector`.

# 1. Create the Utility Package

# -----------------------------

- [ ] 1.1 `flutter create --template=package universal_storage_sync_utils`
- [ ] 1.2 Update `pubspec.yaml` to reflect Flutter dependency.
      name: universal_storage_sync_utils
      description: Utility functions for universal_storage_sync, including a cross-platform folder picker.
      version: 0.1.0
      homepage: <your_repo_url>

      environment:
        sdk: '>=3.3.0 <4.0.0'
        flutter: '>=1.17.0'

      dependencies:
        flutter:
          sdk: flutter
        file_selector: ^1.0.3
        path: ^1.9.0
        permission_handler: ^11.3.1

- [ ] 1.3 Folder structure
      lib/
      src/
      folder_picker.dart
      path_validator.dart
      result.dart # For PickResult sealed class
      universal_storage_sync_utils.dart # exports ↑

# 2. Implement Cross-Platform APIs

# --------------------------------

- [ ] 2.1 `FolderPicker.pickDirectory()`
      • Desktop (Linux, macOS, Windows) & Web: Use `file_selector`'s `getDirectoryPath()`.
      • Mobile (iOS, Android): Throw `UnsupportedError`. The `file_selector` package
      does not support directory selection on mobile platforms.
- [ ] 2.2 `PathValidator.isWritable(String path) → Future<bool>`
      • Try to create and delete a temporary file in the given path.
- [ ] 2.3 Remove `PermissionRequest` class. Integrate permission logic directly
      into the main convenience function.

# 3. Polish Public Surface

# ------------------------

- [ ] 3.1 Define a sealed class for return types in `lib/src/result.dart`.
      ```dart
      sealed class PickResult {}

      class PickSuccess extends PickResult {
        final String path;
        PickSuccess(this.path);
      }

      class PickFailure extends PickResult {
        final FailureReason reason;
        PickFailure(this.reason);
      }

      class PickCancelled extends PickResult {}

      enum FailureReason {
        permissionDenied,
        pathNotWritable,
        platformNotSupported,
      }
      ```

- [ ] 3.2 Create the primary convenience function `pickWritableDirectory()`. - It should combine permission checks, the picker UI, and validation. - Signature: `Future<PickResult> pickWritableDirectory({BuildContext? context})` - Handles `UnsupportedError` from the picker and returns `PickFailure(FailureReason.platformNotSupported)`.

# 4. Migrate Example Todo App

# ---------------------------

- [ ] 4.1 Replace logic in `folder_picker_page.dart` with the new API.
      `dart
    final result = await pickWritableDirectory(context: context);
    switch (result) {
      case PickSuccess(path: final path):
        await appState.setWorkspacePath(path);
        break;
      case PickFailure(reason: final reason):
        // Show error dialog based on reason
        break;
      case PickCancelled():
        // User cancelled, do nothing.
        break;
    }
    `
- [ ] 4.2 Update `pubspec.yaml` in the example app to depend on the new utils package.

# 5. Tests

# --------

- [ ] 5.1 Write unit tests for `PathValidator` (mock `File`).
- [ ] 5.2 Widget test for `FolderPicker` that mocks `file_selector` and verifies behavior on different platforms (especially mobile failure).

# 6. Docs & CI

# ------------

- [ ] 6.1 Add README with usage snippets, clearly stating mobile limitations.
- [ ] 6.2 Update main repo README linking to the new utils package.
- [ ] 6.3 Extend melos workspace; ensure `flutter analyze` & `dart test` pass.

# 7. Publish & PR

# ---------------

- [ ] 7.1 `dart pub publish --dry-run`.
- [ ] 7.2 Push branch, open PR: “feat: Introduce universal_storage_sync_utils”.
- [ ] 7.3 After approval, publish v0.1.0 of utils package.

# Source touch-points

# -------------------

# • Existing logic to extract:

# pkgs/universal_storage_sync/example/todo_app/lib/pages/folder_picker_page.dart

# • Write new utils here:

# pkgs/universal_storage_sync_utils/
