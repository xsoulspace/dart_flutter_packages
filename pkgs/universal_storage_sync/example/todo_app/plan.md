I'll analyze the current state of the universal_storage_sync package and plan the Flutter example application. Let me start by reading the key documents.
Read file: stage_5.md
Read file: plan.md
Let me read the correct files from the universal_storage_sync package:
Read file: pkgs/universal_storage_sync/stage_5.md
Read file: pkgs/universal_storage_sync/plan.md
Now let me also check the current structure and understand what's already implemented:
Read file: pkgs/universal_storage_sync/lib/universal_storage_sync.dart
Ran tool
Perfect! Now I understand the current state. Based on the Stage 5 documentation and the plan, I can see that the universal_storage_sync package is fully implemented with all providers working. Let me plan the Flutter example application.

## 📋 **Flutter Todo App Planning - Universal Storage Sync Demonstration**

### **PDSA Analysis (Plan-Do-Study-Act)**

#### **Cycle 1-5 Strategic Planning:**

**Plan**: Create a comprehensive Flutter app that showcases real-world usage of universal_storage_sync  
**Do**: Design the architecture with VSCode-like folder management + individual todo files  
**Study**: The current package supports FileSystem, OfflineGit, and GitHub API providers perfectly  
**Act**: Build a demo that can switch between storage providers to show versatility

---

## **🎯 Core Application Architecture**

### **1. Folder Management System**

- **VSCode-style folder picker** with native file dialog
- **Persistent storage** of last opened folder using `shared_preferences`
- **Folder validation** ensuring write permissions
- **Breadcrumb navigation** showing current working directory

### **2. Todo File Structure**

```yaml
Selected Folder/
├── todos/
│   ├── todo_001.yaml    # Individual todo files
│   ├── todo_002.yaml
│   └── ...
└── .todo_config.yaml   # App configuration
```

### **3. Storage Provider Integration**

- **Dynamic provider switching** (FileSystem → OfflineGit → GitHub API)
- **Provider-specific UI** showing current sync status
- **Graceful fallbacks** when providers fail
- **Real-time sync indicators**

---

## **🏗️ Technical Implementation Plan**

### **Phase 1: Core Infrastructure**

```dart
// App-level state management
class TodoAppState {
  String? selectedFolderPath;
  StorageProvider currentProvider;
  List<Todo> todos;
  bool isLoading;
  String? errorMessage;
}

// Todo model matching YAML structure
class Todo {
  String id;
  String title;
  String description;
  bool isCompleted;
  DateTime createdAt;
  DateTime? completedAt;
  List<String> tags;
}
```

### **Phase 2: Storage Integration**

```dart
// Wrapper service for provider management
class TodoStorageService {
  late StorageService _storageService;
  late String _baseFolderPath;

  // Initialize with selected folder + provider
  Future<void> initializeProvider(StorageProviderType type, String folderPath);

  // Todo-specific operations
  Future<void> saveTodo(Todo todo);
  Future<Todo?> loadTodo(String todoId);
  Future<List<Todo>> loadAllTodos();
  Future<void> deleteTodo(String todoId);
}
```

### **Phase 3: UI Components**

#### **Folder Management UI**

- `FolderSelectionWidget` - Folder picker + recent folders
- `FolderBreadcrumbWidget` - Current path display
- `ProviderSwitchWidget` - Toggle between storage providers

#### **Todo Management UI**

- `TodoListWidget` - Grid/list view of todos
- `TodoEditorWidget` - Create/edit individual todos
- `TodoCardWidget` - Individual todo display
- `SyncStatusWidget` - Provider sync status

---

## **🚀 Provider-Specific Features Demo**

### **FileSystem Provider**

- **Instant local storage** - No setup required
- **File system watching** - Auto-reload on external changes
- **Bulk operations** - Import/export functionality

### **OfflineGit Provider**

- **Version history** - See todo evolution over time
- **Branch switching** - Different todo contexts
- **Commit visualization** - Git log integration

### **GitHub API Provider**

- **Cross-device sync** - Same todos across devices
- **Collaboration features** - Share todo lists via GitHub
- **Online/offline modes** - Graceful degradation

---

## **📱 UI/UX Flow Design**

### **Initial App Launch**

1. **Splash screen** → Check for previous folder
2. **Folder selection** → Native file picker or recent folders
3. **Provider selection** → Choose storage backend
4. **Todo list view** → Main application interface

### **Primary User Journey**

```
Open Folder → Select Provider → View Todos → Create/Edit → Auto-Save → Sync (if supported)
     ↓              ↓            ↓           ↓          ↓            ↓
  VSCode-like    FileSystem    YAML files   Form UI   Background   Status UI
  experience     Git/GitHub    individual   validation operations  indicators
```

### **Advanced Features**

- **Search & filter** todos across all files
- **Bulk operations** (mark complete, delete, export)
- **Settings panel** for provider configuration
- **Sync conflict resolution** UI for Git providers

---

## **🎨 Technical Stack**

### **Flutter Dependencies**

```yaml
dependencies:
  flutter: sdk
  universal_storage_sync: ^1.0.0
  file_picker: ^6.0.0 # Folder selection
  shared_preferences: ^2.2.0 # Persist last folder
  yaml: ^3.1.2 # Todo file format
  provider: ^2.4.0 # State management + ChangeNotifier
  go_router: ^12.0.0 # Navigation
  flutter_animate: ^4.3.0 # UI animations
```

### **macOS-Specific Setup**

```xml
<!-- macos/Runner/DebugProfile.entitlements -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

---

## **📊 Success Metrics & Demo Scenarios**

### **Core Functionality Validation**

- ✅ **Folder persistence** - Remembers last opened folder across sessions
- ✅ **File operations** - Create, read, update, delete todos seamlessly
- ✅ **Provider switching** - Change storage backend without data loss
- ✅ **Sync operations** - Git/GitHub sync with conflict resolution

### **Demo Scenarios**

1. **Local Development** - FileSystem provider for quick prototyping
2. **Version Control** - OfflineGit for tracking todo changes
3. **Team Collaboration** - GitHub API for shared todo lists
4. **Offline Resilience** - Works without internet, syncs when available

---

## **🔄 Next Steps**

**Immediate Actions:**

1. Create Flutter app project structure
2. Implement folder selection with persistence
3. Design Todo model and YAML serialization
4. Build basic CRUD operations with FileSystem provider
5. Add provider switching capability
6. Implement Git and GitHub provider integration
7. Polish UI/UX and add advanced features

This plan creates a **real-world demonstration** of the universal_storage_sync package that's both **functionally complete** and **educationally valuable** for developers evaluating the package.
