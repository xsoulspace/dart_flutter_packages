# AI Agent Instructions: macOS Persistent File Access Setup

**Goal:** Configure a Flutter project to allow persistent, sandboxed access to user-selected files and folders on macOS. This is required for features that must remember and re-access a directory across app launches.

**Prerequisite:** The target project must have a standard Flutter `macos` directory.

---

### Step 1: Add Dependency

To programmatically manage security-scoped bookmarks, the project requires the `universal_storage_sync_utils` package.

**Action:** Modify the `pubspec.yaml` file.
**Instruction:** Add the following line under the `dependencies` section.

```yaml
universal_storage_sync_utils: ^0.1.0
```

After modifying, execute `flutter pub get` in the project root.

---

### Step 2: Configure macOS Entitlements

The application needs specific permissions to request and persist file system access. These must be added to both debug and release configurations.

#### 2.1 Update Debug Profile

**Action:** Modify the file at `macos/Runner/DebugProfile.entitlements`.
**Instruction:** Ensure the `<dict>` in the file contains the following keys. Add any that are missing.

```xml
<!-- For allowing the user to select files/folders -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<!-- For creating and resolving security-scoped bookmarks -->
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

#### 2.2 Update Release Profile

**Action:** Modify the file at `macos/Runner/Release.entitlements`.
**Instruction:** Ensure the `<dict>` in the file contains the same keys as the debug profile. Add any that are missing.

```xml
<!-- For allowing the user to select files/folders -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<!-- For creating and resolving security-scoped bookmarks -->
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

---

**Completion:** The project is now configured. The Dart code can use the `macos_secure_bookmarks` package provided by the `universal_storage_sync_utils` package to implement persistent file access.
