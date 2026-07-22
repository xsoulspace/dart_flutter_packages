// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_file_app/models/todo.dart';
import 'package:todo_file_app/state/app_state.dart';
import 'package:todo_file_app/widgets/status_bar.dart';
import 'package:todo_file_app/widgets/todo_editor_dialog.dart';

/// {@template todo_list_page}
/// Main page displaying the list of todos with CRUD operations.
/// {@endtemplate}
class TodoListPage extends StatelessWidget {
  /// {@macro todo_list_page}
  const TodoListPage({super.key});

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Todo App'),
      actions: [
        // Refresh button
        Consumer<AppState>(
          builder: (final context, final appState, final child) => IconButton(
            onPressed: appState.busy ? null : appState.loadTodos,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh todos',
          ),
        ),

        // Settings/workspace button
        PopupMenuButton<String>(
          onSelected: (final value) {
            if (value == 'change_workspace') {
              _showChangeWorkspaceDialog(context);
            }
          },
          itemBuilder: (final context) => [
            const PopupMenuItem(
              value: 'change_workspace',
              child: Row(
                children: [
                  Icon(Icons.folder_open),
                  SizedBox(width: 8),
                  Text('Change Workspace'),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        // Status bar
        const StatusBar(),

        // ignore: flutter_style_todos
        // Todo list
        Expanded(
          child: Consumer<AppState>(
            builder: (final context, final appState, final child) {
              if (appState.busy) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading todos...'),
                    ],
                  ),
                );
              }

              if (appState.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Error: ${appState.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: appState.loadTodos,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (appState.todos.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No todos yet',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button to create your first todo',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: appState.todos.length,
                itemBuilder: (final context, final index) {
                  final todo = appState.todos[index];
                  return _TodoListItem(todo: todo);
                },
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: Consumer<AppState>(
      builder: (final context, final appState, final child) =>
          FloatingActionButton(
            onPressed: appState.busy ? null : () => _showAddTodoDialog(context),
            child: const Icon(Icons.add),
          ),
    ),
  );

  void _showAddTodoDialog(final BuildContext context) => showDialog<void>(
    context: context,
    builder: (final context) => const TodoEditorDialog(),
  );

  void _showChangeWorkspaceDialog(
    final BuildContext context,
  ) => showDialog<void>(
    context: context,
    builder: (final context) => AlertDialog(
      title: const Text('Change Workspace'),
      content: const Text(
        'Are you sure you want to change the workspace folder? '
        "This will close the current workspace and you'll need to select a new folder.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.read<AppState>().clearWorkspace();
          },
          child: const Text('Change'),
        ),
      ],
    ),
  );
}

/// Individual todo item widget
class _TodoListItem extends StatelessWidget {
  const _TodoListItem({required this.todo});

  final Todo todo;

  @override
  Widget build(final BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Checkbox(
        value: todo.isCompleted,
        onChanged: (final value) =>
            context.read<AppState>().toggleTodoCompletion(todo.id),
      ),
      title: Text(
        todo.title,
        style: todo.isCompleted
            ? const TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Colors.grey,
              )
            : null,
      ),
      subtitle: todo.description.isNotEmpty
          ? Text(
              todo.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: todo.isCompleted
                  ? const TextStyle(color: Colors.grey)
                  : null,
            )
          : null,
      trailing: PopupMenuButton<String>(
        onSelected: (final value) {
          switch (value) {
            case 'edit':
              _showEditDialog(context);
            case 'delete':
              _showDeleteDialog(context);
          }
        },
        itemBuilder: (final context) => [
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [Icon(Icons.edit), SizedBox(width: 8), Text('Edit')],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void _showEditDialog(final BuildContext context) => showDialog<void>(
    context: context,
    builder: (final context) => TodoEditorDialog(todo: todo),
  );

  void _showDeleteDialog(final BuildContext context) => showDialog<void>(
    context: context,
    builder: (final context) => AlertDialog(
      title: const Text('Delete Todo'),
      content: Text('Are you sure you want to delete "${todo.title}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await context.read<AppState>().deleteTodo(todo.id);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
