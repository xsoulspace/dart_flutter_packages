## 0. TL ; DR

Build a macOS Flutter demo that proves universal_storage_sync’s FileSystem provider via:

1. VS Code–style folder picker that persists the last-used directory.
2. CRUD operations on todos where **each todo is a single YAML file**.
3. Provider/ChangeNotifier state-management (no Riverpod, no Git/PAT, no cloud).

Success = green unit + widget + integration tests, clear README, and usage of the new **FileSystemConfig.builder()** API (Stage-5 requirement).

---

## 1. Scope & Goals

✔ Folder selection and persistence  
✔ Create / Read / Update / Delete todos  
✔ Basic list & editor UI  
✔ Error handling for read-only / invalid folders  
✖ Git / GitHub / remote sync  
✖ File-watchers, merge conflict UI, collaboration features

---

## 2. Filesystem Layout & Data Model

```
<workspace>/
└── todos/
    ├── e3b1c0d9-…​.yaml
    └── …
```

YAML schema for a todo:

```yaml
id: e3b1c0d9-…
title: "Buy milk"
description: "2 L oat milk"
isCompleted: false
createdAt: 2025-06-18T09:22:15Z
completedAt: null
tags: ["groceries"]
```

• Filenames use `uuid_v4` to avoid collisions.  
• The `todos/` directory is lazily created on first save.

---

## 3. Structured Config Validation

```dart
final config = FileSystemConfig.builder()
  .basePath(workspacePath)
  .build();

await storageService.initialize(config);
```

This exercises Stage-5’s new typed builder API instead of raw `Map`.

---

## 4. State-Management Stack

```dart
class AppState extends ChangeNotifier {
  String? workspacePath;         // persisted in SharedPreferences
  List<Todo> todos = [];
  bool busy = false;
  String? error;

  Future<void> pickFolder();     // folder selection + persistence
  Future<void> loadTodos();      // reads all YAML files
  Future<void> saveTodo(Todo t); // create/update
  Future<void> deleteTodo(String id);
}
```

Registered with:

```dart
runApp(
  ChangeNotifierProvider(
    create: (_) => AppState(),
    child: const TodoApp(),
  ),
);
```

---

## 5. UI Blueprint

1. **Splash / Bootstrap** – checks stored folder, routes accordingly.
2. **FolderPickerPage** – `file_selector` dialog, recent folders list.
3. **TodoListPage** – list of todos, FAB to add.
4. **TodoEditorDialog** – form to create/edit.
5. **StatusBar** – shows workspace path & todo count.

All widgets ≤50 LOC when possible (see flutter_ui_dev rules).

---

## 6. Error Handling & UX

• Wrap storage calls in `try … on StorageException` → SnackBar.  
• Detect read-only directories → explanatory dialog with “Choose another folder”.  
• Guard against >1 GB folder size with a soft limit warning.

---

## 7. macOS Specifics

`macos/Runner/DebugProfile.entitlements`

```xml
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

Add hardened-runtime & notarisation notes in README for external testers.

---

## 8. Dependencies

```yaml
dependencies:
  flutter: sdk
  universal_storage_sync: ^1.0.0
  file_selector: ^1.1.0 # folder picker (supports macOS)
  shared_preferences: ^2.2.0
  yaml: ^3.1.2
  provider: ^6.0.5
  go_router: ^12.0.0 # simple routing
  flutter_animate: ^4.3.0 # optional UI polish
dev_dependencies:
  flutter_test:
  integration_test:
  mocktail: ^1.0.0
```

---

## 9. Testing Strategy

• **Unit** – FileSystemConfigBuilder validation, AppState CRUD with mocked StorageService.  
• **Widget** – FolderPickerPage, TodoEditorDialog save flow.  
• **Integration** – happy-path: pick folder → add todo → restart → todo persists.

---

## 10. Documentation Deliverables

`/example/README.md` must include:

1. Build/run steps & macOS entitlements.
2. Limitations (FileSystem-only, no sync).
3. Link to Stage-5 structured-config docs.

Code: add dartdoc to public classes, use `{@template}` / `{@macro}` snippets.

---

## 11. Milestones

| Week | Deliverable                                      |
| ---- | ------------------------------------------------ |
| 0    | Project skeleton, entitlements, FolderPickerPage |
| 1    | AppState + FileSystemConfig builder + CRUD wired |
| 2    | Unit & widget tests, error handling polish       |
| 3    | Integration test, README, UI polish, internal QA |

---

## 12. Risks & Mitigations

| Risk                         | Mitigation                   |
| ---------------------------- | ---------------------------- |
| User selects massive folder  | Size check & warning dialog  |
| SharedPreferences corruption | Fallback to FolderPickerPage |
| Sandbox permission denied    | Clear error with help link   |

---

## 13. Immediate Next Steps

1. Create `example/todo_app` Flutter project scaffold.
2. Implement FileSelector + SharedPreferences persistence.
3. Add `FileSystemConfig.builder()` usage with `StorageService`.
4. Basic Todo model (`freezed` optional) + YAML helpers.
5. Build TodoListPage & TodoEditorDialog.
6. Write first unit test (AppState.loadTodos).
