library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import 'logger_inspector_controller.dart';

/// Lightweight logs/traces/issues inspector for Flutter apps.
final class LoggerInspectorView extends StatefulWidget {
  const LoggerInspectorView({
    required this.controller,
    this.autoInit = true,
    super.key,
  });

  final LoggerInspectorController controller;
  final bool autoInit;

  @override
  State<LoggerInspectorView> createState() => _LoggerInspectorViewState();
}

final class _LoggerInspectorViewState extends State<LoggerInspectorView> {
  late final TextEditingController _searchController;
  late Set<LogLevel> _selectedLevels;

  String? _selectedCategory;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedLevels = LogLevel.values.toSet();

    widget.controller.addListener(_onControllerChanged);
    if (widget.autoInit) {
      unawaited(widget.controller.init());
    }
  }

  @override
  void didUpdateWidget(final LoggerInspectorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      if (widget.autoInit) {
        unawaited(widget.controller.init());
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(final BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchAndFilters(context),
          const TabBar(
            tabs: <Tab>[
              Tab(text: 'Logs'),
              Tab(text: 'Traces'),
              Tab(text: 'Issues'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _buildLogsTab(context),
                _buildTracesTab(context),
                _buildIssuesTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(final BuildContext context) {
    final categories =
        widget.controller.logs
            .map((final record) => record.category)
            .toSet()
            .toList(growable: false)
          ..sort();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _searchController,
            onChanged: (final value) {
              setState(() {
                _searchText = value.trim().toLowerCase();
              });
            },
            decoration: const InputDecoration(
              hintText: 'Search message/category/fields',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LogLevel.values
                .map(
                  (final level) => FilterChip(
                    label: Text(level.name),
                    selected: _selectedLevels.contains(level),
                    onSelected: (final selected) {
                      setState(() {
                        if (selected) {
                          _selectedLevels.add(level);
                        } else {
                          _selectedLevels.remove(level);
                        }
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          DropdownButton<String?>(
            isExpanded: true,
            value: _selectedCategory,
            hint: const Text('All categories'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All categories'),
              ),
              ...categories.map(
                (final category) => DropdownMenuItem<String?>(
                  value: category,
                  child: Text(category),
                ),
              ),
            ],
            onChanged: (final value) {
              setState(() {
                _selectedCategory = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab(final BuildContext context) {
    final logs = _filteredLogs();

    if (widget.controller.isLoading && logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (logs.isEmpty) {
      return const Center(child: Text('No logs for current filters.'));
    }

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (final context, final index) {
        final record = logs[index];
        return _buildLogTile(context, record);
      },
    );
  }

  Widget _buildLogTile(final BuildContext context, final LogRecord record) {
    final traceId = record.trace?.traceId;

    return ListTile(
      leading: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: _levelColor(record.level),
          shape: BoxShape.circle,
        ),
      ),
      title: Text(record.message),
      subtitle: Text(
        '${record.timestampUtc.toIso8601String()} | '
        '${record.level.name.toUpperCase()} | '
        '${record.category}',
      ),
      trailing: traceId == null
          ? null
          : TextButton(
              onPressed: () async {
                await widget.controller.openTrace(traceId);
                if (!context.mounted) {
                  return;
                }
                DefaultTabController.of(context).animateTo(1);
              },
              child: const Text('Trace'),
            ),
    );
  }

  Widget _buildTracesTab(final BuildContext context) {
    final traceId = widget.controller.selectedTraceId;
    final traceRecords = widget.controller.traceRecords;

    if (traceId == null) {
      return const Center(
        child: Text('Select a trace from Logs tab to inspect chain ordering.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(child: Text('Trace: $traceId')),
              TextButton(
                onPressed: widget.controller.clearTrace,
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: traceRecords.isEmpty
              ? const Center(child: Text('No records in this trace.'))
              : ListView.builder(
                  itemCount: traceRecords.length,
                  itemBuilder: (final context, final index) {
                    final record = traceRecords[index];
                    return ListTile(
                      leading: Text('${record.sequence}'),
                      title: Text(record.message),
                      subtitle: Text(
                        '${record.level.name.toUpperCase()} | ${record.category}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildIssuesTab(final BuildContext context) {
    final issues = widget.controller.issues;
    if (issues.isEmpty) {
      return const Center(child: Text('No grouped issues yet.'));
    }

    return ListView.builder(
      itemCount: issues.length,
      itemBuilder: (final context, final index) {
        final issue = issues[index];
        final fingerprintLabel = issue.fingerprint.length > 12
            ? issue.fingerprint.substring(0, 12)
            : issue.fingerprint;

        return ListTile(
          leading: Icon(
            issue.escalated ? Icons.priority_high : Icons.bug_report_outlined,
            color: issue.escalated
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            '[$fingerprintLabel] ${issue.highestLevel.name.toUpperCase()}',
          ),
          subtitle: Text(
            'status=${issue.status.name} '
            'occurrences24h=${issue.occurrences24h} '
            'score=${issue.priorityScore.toStringAsFixed(1)}',
          ),
          isThreeLine: false,
        );
      },
    );
  }

  List<LogRecord> _filteredLogs() {
    return widget.controller.logs
        .where((final record) {
          if (!_selectedLevels.contains(record.level)) {
            return false;
          }
          if (_selectedCategory != null &&
              record.category != _selectedCategory) {
            return false;
          }
          if (_searchText.isEmpty) {
            return true;
          }

          final haystack = StringBuffer()
            ..write(record.message)
            ..write(' ')
            ..write(record.category)
            ..write(' ')
            ..write(record.error?.toString() ?? '');

          record.fields.forEach((final key, final value) {
            haystack
              ..write(' ')
              ..write(key)
              ..write('=')
              ..write(value);
          });

          return haystack.toString().toLowerCase().contains(_searchText);
        })
        .toList(growable: false);
  }

  Color _levelColor(final LogLevel level) => switch (level) {
    LogLevel.trace => Colors.blueGrey,
    LogLevel.debug => Colors.blue,
    LogLevel.info => Colors.green,
    LogLevel.warning => Colors.orange,
    LogLevel.error => Colors.red,
    LogLevel.critical => Colors.red.shade900,
  };
}
