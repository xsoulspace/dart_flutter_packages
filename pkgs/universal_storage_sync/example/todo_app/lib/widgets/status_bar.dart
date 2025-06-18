import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// {@template status_bar}
/// Status bar showing workspace path and todo statistics.
/// {@endtemplate}
class StatusBar extends StatelessWidget {
  /// {@macro status_bar}
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AppState>(
    builder: (context, appState, child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Workspace path
          Icon(Icons.folder, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              appState.workspacePath ?? 'No workspace selected',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Todo statistics
          if (appState.hasWorkspace) ...[
            const SizedBox(width: 16),
            _buildStat(
              context,
              Icons.pending_actions,
              '${appState.pendingCount}',
              'Pending',
            ),
            const SizedBox(width: 16),
            _buildStat(
              context,
              Icons.check_circle,
              '${appState.completedCount}',
              'Completed',
            ),
            const SizedBox(width: 16),
            _buildStat(
              context,
              Icons.list,
              '${appState.todos.length}',
              'Total',
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildStat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) => Tooltip(
    message: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
