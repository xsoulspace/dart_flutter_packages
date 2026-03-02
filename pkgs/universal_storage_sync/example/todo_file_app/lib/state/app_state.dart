// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import '../models/todo.dart';

/// {@template app_state}
/// Main application state managing workspace, todos, and storage operations.
/// Uses ChangeNotifier for reactive UI updates.
/// {@endtemplate}
class AppState extends ChangeNotifier {
  static const String _workspacePathKey = 'workspace_path';
  static const String _todosDirectoryName = 'todos';
  final Uuid _uuid = const Uuid();

  FilePathConfig filePathConfig = FilePathConfig.empty;

  /// List of all todos
  List<Todo> todos = [];

  /// Whether the app is currently busy with an operation
  bool busy = false;

  /// Current error message, null if no error
  String? error;

  /// Storage service instance
  StorageService? _legacyStorageService;
  StorageKernel? _kernel;
  StorageServiceKernelAdapter? _storageAdapter;

  /// {@macro app_state}
  AppState() {
    _onLoad();
  }

  /// Whether a workspace is currently selected
  bool get hasWorkspace => filePathConfig.isNotEmpty;

  /// Number of completed todos
  int get completedCount => todos.where((todo) => todo.isCompleted).length;

  /// Number of pending todos
  int get pendingCount => todos.where((todo) => !todo.isCompleted).length;

  /// Whether app storage is currently routed through profile-based kernel.
  bool get usesProfileKernel => _kernel != null;

  /// Sets the workspace path and initializes storage
  Future<void> setWorkspacePath(final FilePathConfig pathConfig) async {
    await _setBusy(true);
    try {
      final isWritable = PathValidator.isWritable(pathConfig.path.path);
      if (!isWritable) {
        throw Exception('Directory is not writable: ${pathConfig.path.path}');
      }

      await _storeWorkspacePath(pathConfig);
      await _initializeStorage();
      await loadTodos();
      _clearError();
    } catch (e) {
      _setError('Failed to set workspace: $e');
    } finally {
      await _setBusy(false);
    }
  }

  /// Loads all todos from the workspace
  Future<void> loadTodos() async {
    if (!hasWorkspace) return;

    await _setBusy(true);
    try {
      const todosPath = _todosDirectoryName;
      final fileList = await _listDirectory(todosPath);

      final loadedTodos = <Todo>[];
      for (final fileEntry in fileList) {
        final fileName = fileEntry.name;
        if (fileName.endsWith('.yaml')) {
          final content = await _readFile(fileName);
          if (content != null) {
            try {
              final yamlData = loadYaml(content) as Map;
              final todoData = Map<String, dynamic>.from(yamlData);
              loadedTodos.add(Todo.fromJson(todoData));
            } catch (e) {
              print('Failed to parse todo file $fileName: $e');
            }
          }
        }
      }

      todos = loadedTodos;
      _clearError();
    } catch (e) {
      _setError('Failed to load todos: $e');
      todos = [];
    } finally {
      await _setBusy(false);
    }
  }

  /// Creates or updates a todo
  Future<void> saveTodo(Todo todo) async {
    if (!hasWorkspace) return;

    await _setBusy(true);
    try {
      final fileName = '$_todosDirectoryName/${todo.id.value}.yaml';
      final yamlContent = _todoToYaml(todo);

      await _saveFile(
        fileName,
        yamlContent,
        message: 'Save todo: ${todo.title}',
      );

      // Update local list
      final existingIndex = todos.indexWhere(
        (t) => t.id.value == todo.id.value,
      );
      if (existingIndex >= 0) {
        todos[existingIndex] = todo;
      } else {
        todos.add(todo);
      }

      _clearError();
    } catch (e) {
      _setError('Failed to save todo: $e');
    } finally {
      await _setBusy(false);
    }
  }

  /// Deletes a todo
  Future<void> deleteTodo(TodoId id) async {
    if (!hasWorkspace) return;

    await _setBusy(true);
    try {
      final fileName = '$_todosDirectoryName/${id.value}.yaml';
      await _removeFile(fileName, message: 'Delete todo: $id');

      // Remove from local list
      todos.removeWhere((todo) => todo.id.value == id.value);
      _clearError();
    } catch (e) {
      _setError('Failed to delete todo: $e');
    } finally {
      await _setBusy(false);
    }
  }

  /// Creates a new todo with generated ID
  Future<void> createTodo({
    required String title,
    String description = '',
    List<String> tags = const [],
  }) async {
    final todo = Todo.create(
      id: TodoId(_uuid.v4()),
      title: title,
      description: description,
      tags: tags,
    );
    await saveTodo(todo);
  }

  /// Toggles completion status of a todo
  Future<void> toggleTodoCompletion(TodoId id) async {
    final todo = todos.firstWhere((t) => t.id.value == id.value);
    final updatedTodo = todo.copyWith(
      isCompleted: !todo.isCompleted,
      completedAt: !todo.isCompleted ? DateTime.now() : null,
    );
    await saveTodo(updatedTodo);
  }

  /// Clears the current workspace
  void clearWorkspace() {
    filePathConfig = FilePathConfig.empty;
    todos = [];
    _storageAdapter = null;
    _kernel = null;
    _legacyStorageService = null;
    _clearStoredWorkspacePath();
    notifyListeners();
  }

  // Private methods

  Future<void> _setBusy(bool value) async {
    busy = value;
    notifyListeners();
  }

  void _setError(String message) {
    error = message;
    notifyListeners();
  }

  void _clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> _onLoad() async {
    StorageProviderRegistry.register<FileSystemConfig>(
      () => FileSystemStorageProvider(),
    );
    await _loadStoredWorkspacePath();
  }

  Future<void> _loadStoredWorkspacePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workspacePath = prefs.getString(_workspacePathKey);
      filePathConfig = FilePathConfig.fromJson(workspacePath);

      await _initializeStorage();
      await loadTodos();
    } catch (e) {
      print('Failed to load stored workspace path: $e');
    }
  }

  Future<void> _storeWorkspacePath(final FilePathConfig pathConfig) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_workspacePathKey, jsonEncode(pathConfig.toJson()));
    } catch (e) {
      print('Failed to store workspace path: $e');
    }
  }

  Future<void> _clearStoredWorkspacePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_workspacePathKey);
    } catch (e) {
      print('Failed to clear stored workspace path: $e');
    }
  }

  Future<void> _initializeStorage() async {
    if (!hasWorkspace) return;

    resolvePlatformDirectoryOfConfig(filePathConfig);

    final fileSystemConfig = FileSystemConfig.fromFilePathConfig(
      filePathConfig,
    );
    _legacyStorageService = await StorageFactory.create(fileSystemConfig);

    final profile = const StorageProfile(
      name: 'todo_file_app_profile_v1',
      namespaces: <StorageNamespaceProfile>[
        StorageNamespaceProfile(
          namespace: StorageNamespace.projects,
          policy: StoragePolicy.localOnly,
          localEngineId: 'filesystem',
          defaultFileExtension: '.yaml',
          syncInteractionLevel: SyncInteractionLevel.minimal,
        ),
      ],
    );

    final loadResult = await const StorageProfileLoader().load(
      profile: profile,
      serviceFactory: (final _) async => _legacyStorageService!,
    );
    _kernel = loadResult.kernel;
    _storageAdapter = StorageServiceKernelAdapter(
      kernel: _kernel!,
      namespace: StorageNamespace.projects,
    );
  }

  Future<List<FileEntry>> _listDirectory(final String path) async {
    if (_storageAdapter != null) {
      return _storageAdapter!.listDirectory(path);
    }
    return _legacyStorageService!.listDirectory(path);
  }

  Future<String?> _readFile(final String path) async {
    if (_storageAdapter != null) {
      return _storageAdapter!.readFile(path);
    }
    return _legacyStorageService!.readFile(path);
  }

  Future<FileOperationResult> _saveFile(
    final String path,
    final String content, {
    final String? message,
  }) async {
    if (_storageAdapter != null) {
      return _storageAdapter!.saveFile(path, content, message: message);
    }
    return _legacyStorageService!.saveFile(path, content, message: message);
  }

  Future<FileOperationResult> _removeFile(
    final String path, {
    final String? message,
  }) async {
    if (_storageAdapter != null) {
      return _storageAdapter!.removeFile(path, message: message);
    }
    return _legacyStorageService!.removeFile(path, message: message);
  }

  String _todoToYaml(Todo todo) {
    final data = {
      'id': todo.id.value,
      'title': todo.title,
      'description': todo.description,
      'isCompleted': todo.isCompleted,
      'createdAt': todo.createdAt.toIso8601String(),
      'completedAt': todo.completedAt?.toIso8601String(),
      'tags': todo.tags,
    };

    // Simple YAML serialization
    final buffer = StringBuffer();
    for (final entry in data.entries) {
      if (entry.value != null) {
        if (entry.value is List) {
          buffer.writeln('${entry.key}:');
          for (final item in entry.value as List) {
            buffer.writeln('  - ${_yamlEscape(item.toString())}');
          }
        } else {
          buffer.writeln(
            '${entry.key}: ${_yamlEscape(entry.value.toString())}',
          );
        }
      }
    }
    return buffer.toString();
  }

  String _yamlEscape(String value) {
    // Simple YAML escaping - wrap in quotes if contains special characters
    if (value.contains(':') || value.contains('#') || value.contains('\n')) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return value;
  }
}
