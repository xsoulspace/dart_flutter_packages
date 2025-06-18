import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo.dart';
import '../state/app_state.dart';
import '../widgets/status_bar.dart';
import '../widgets/todo_editor_dialog.dart';

/// {@template todo_list_page}
/// Main page displaying the list of todos with CRUD operations.
/// {@endtemplate}
class TodoListPage extends StatelessWidget {
  /// {@macro todo_list_page}
  const TodoListPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Todo App'),
      actions: [
        // Refresh button
        Consumer<AppState>(
          builder: (context, appState, child) => IconButton(
            onPressed: appState.busy ? null : () => appState.loadTodos(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh todos',
          ),
        ),

        // Settings/workspace button
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'change_workspace') {
              _showChangeWorkspaceDialog(context);
            }
          },
          itemBuilder: (context) => [
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

        // Todo list
        Expanded(
          child: Consumer<AppState>(
            builder: (context, appState, child) {
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
                        onPressed: () => appState.loadTodos(),
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
                itemBuilder: (context, index) {
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
      builder: (context, appState, child) => FloatingActionButton(
        onPressed: appState.busy ? null : () => _showAddTodoDialog(context),
        child: const Icon(Icons.add),
      ),
    ),
  );

  void _showAddTodoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const TodoEditorDialog(),
    );
  }

  void _showChangeWorkspaceDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Workspace'),
        content: const Text(
          'Are you sure you want to change the workspace folder? '
          'This will close the current workspace and you\'ll need to select a new folder.',
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
}

/// Individual todo item widget
class _TodoListItem extends StatelessWidget {
  const _TodoListItem({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Checkbox(
        value: todo.isCompleted,
        onChanged: (value) {
          context.read<AppState>().toggleTodoCompletion(todo.id);
        },
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
        onSelected: (value) {
          switch (value) {
            case 'edit':
              _showEditDialog(context);
              break;
            case 'delete':
              _showDeleteDialog(context);
              break;
          }
        },
        itemBuilder: (context) => [
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

  void _showEditDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => TodoEditorDialog(todo: todo),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Todo'),
        content: Text('Are you sure you want to delete "${todo.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<AppState>().deleteTodo(todo.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
