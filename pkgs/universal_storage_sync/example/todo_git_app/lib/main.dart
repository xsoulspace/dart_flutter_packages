import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/folder_picker_page.dart';
import 'pages/todo_list_page.dart';
import 'state/app_state.dart';

void main() {
  runApp(const TodoApp());
}

/// {@template todo_app}
/// Main Todo application with state management and routing.
/// {@endtemplate}
class TodoApp extends StatelessWidget {
  /// {@macro todo_app}
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          title: 'Todo App - Universal Storage Sync Demo',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: const _AppRouter(),
        ),
      );
}

/// {@template app_router}
/// Router widget that switches between folder picker and todo list
/// based on whether a workspace is selected.
/// {@endtemplate}
class _AppRouter extends StatelessWidget {
  /// {@macro app_router}
  const _AppRouter();

  @override
  Widget build(BuildContext context) => Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.hasWorkspace) {
            return const TodoListPage();
          } else {
            return const FolderPickerPage();
          }
        },
      );
}
