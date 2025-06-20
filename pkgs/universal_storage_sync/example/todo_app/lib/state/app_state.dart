import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
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

  /// Current workspace path
  String? workspacePath;

  /// List of all todos
  List<Todo> todos = [];

  /// Whether the app is currently busy with an operation
  bool busy = false;

  /// Current error message, null if no error
  String? error;

  /// Storage service instance
  StorageService? _storageService;

  /// {@macro app_state}
  AppState() {
    _loadStoredWorkspacePath();
  }

  /// Whether a workspace is currently selected
  bool get hasWorkspace => workspacePath != null;

  /// Number of completed todos
  int get completedCount => todos.where((todo) => todo.isCompleted).length;

  /// Number of pending todos
  int get pendingCount => todos.where((todo) => !todo.isCompleted).length;

  /// Sets the workspace path and initializes storage
  Future<void> setWorkspacePath(String pathValue) async {
    await _setBusy(true);
    try {
      // Validate directory exists and is writable
      final directory = Directory(pathValue);
      if (!await directory.exists()) {
        throw Exception('Directory does not exist: $pathValue');
      }

      // Test write permissions by creating a temporary file
      final testFile = File(path.join(pathValue, '.todo_app_test'));
      try {
        await testFile.writeAsString('test');
        await testFile.delete();
      } catch (e) {
        throw Exception('Directory is not writable: $pathValue');
      }

      workspacePath = pathValue;
      await _storeWorkspacePath(pathValue);
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
      final fileList = await _storageService!.listDirectory(todosPath);

      final loadedTodos = <Todo>[];
      for (final fileName in fileList) {
        if (fileName.endsWith('.yaml')) {
          final content = await _storageService!.readFile(fileName);
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

      await _storageService!.saveFile(
        fileName,
        yamlContent,
        message: 'Save todo: ${todo.title}',
      );

      // Update local list
      final existingIndex =
          todos.indexWhere((t) => t.id.value == todo.id.value);
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
      await _storageService!.removeFile(
        fileName,
        message: 'Delete todo: $id',
      );

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
    workspacePath = null;
    todos = [];
    _storageService = null;
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

  Future<void> _loadStoredWorkspacePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_workspacePathKey);
      if (stored != null && Directory(stored).existsSync()) {
        workspacePath = stored;
        await _initializeStorage();
        await loadTodos();
      }
    } catch (e) {
      print('Failed to load stored workspace path: $e');
    }
  }

  Future<void> _storeWorkspacePath(String pathValue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_workspacePathKey, pathValue);
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
    if (workspacePath == null) return;

    final config = FileSystemConfig(basePath: workspacePath!);

    _storageService = StorageService(FileSystemStorageProvider());
    await _storageService!.initializeWithConfig(config);
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
          buffer
              .writeln('${entry.key}: ${_yamlEscape(entry.value.toString())}');
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
