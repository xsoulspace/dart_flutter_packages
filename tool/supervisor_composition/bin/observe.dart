/// Observe-only converge bridge for the dfp model composition (oka
/// ADR-0040 R1; the oka supervisor guide roadmap step "dfp model
/// composition on the shipped substrate").
///
///   dart run bin/observe.dart [--project <dfp-root>] [--port <n>]
///       [--json] [--facts <file.jsonl>]
///
/// Never spawns, never signals: converge runs with `apply: false` and the
/// only provider bound is [ObserveOnlyProvider], whose `start` throws.
library;

import 'dart:convert';
import 'dart:io';

import 'package:oka_supervisor/oka_supervisor.dart';
import 'package:resource_composition/resource_composition.dart';

import 'package:supervisor_composition/desired.dart';

Future<void> main(final List<String> args) async {
  var project = _defaultProjectRoot();
  var port = ModelServeFacts.port;
  var json = false;
  String? factsPath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--project' && i + 1 < args.length) {
      project = args[++i];
    } else if (arg.startsWith('--project=')) {
      project = arg.split('=').last;
    } else if (arg == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else if (arg.startsWith('--port=')) {
      port = int.parse(arg.split('=').last);
    } else if (arg == '--json') {
      json = true;
    } else if (arg == '--facts' && i + 1 < args.length) {
      factsPath = args[++i];
    } else if (arg.startsWith('--facts=')) {
      factsPath = arg.split('=').last;
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 2;
      return;
    }
  }

  final desired = desiredComposition(port: port);
  final supervisor = Supervisor(projectRoot: project);
  final events = CollectingEvidenceSink();
  final report = await supervisor.converge(
    desired: desired,
    factory: _observeOnlyFactory,
    evidence: events,
    apply: false,
  );

  stdout
    ..writeln('project: $project (scope ${supervisor.scope})')
    ..writeln('mode: observe-only (apply: false; never spawns, never '
        'signals)')
    ..write(report.describe());

  if (json) {
    final statuses = projectStatus(
      snapshot: supervisor.registry.snapshot(supervisor.scope),
      desired: desired,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'project': project,
        'scope': supervisor.scope,
        'status': jsonDecode(statusJson(statuses: statuses)),
        'converge': <String, Object?>{
          'apply': false,
          'started': report.started,
          'restarted': report.restarted,
          'failedStarts': report.failedStarts,
          'invalid': report.invalid,
          'actions': <Object?>[
            for (final action in report.plan.actions)
              <String, String?>{
                'kind': action.kind.name,
                'componentId': action.componentId,
                'reason': action.reason,
              },
          ],
          'findings': <Object?>[
            for (final finding in report.plan.findings)
              <String, String?>{
                'code': finding.code,
                'componentId': finding.componentId,
                'message': finding.message,
              },
          ],
          'events': <Object?>[
            for (final event in events.events) jsonDecode(event.toJsonLine()),
          ],
        },
      }),
    );
  }

  if (factsPath != null) {
    final sink = File(factsPath).openWrite(mode: FileMode.append);
    for (final event in events.events) {
      sink.writeln(event.toJsonLine());
    }
    await sink.flush();
    await sink.close();
    stdout.writeln('facts appended: $factsPath');
  }

  if (report.invalid) exitCode = 2;
}

ResourceProvider _observeOnlyFactory(final String name) {
  if (name == ObserveOnlyProvider.name) return const ObserveOnlyProvider();
  throw ArgumentError(
    'unknown provider name: $name (this composition binds only '
    '${ObserveOnlyProvider.name})',
  );
}

/// The dfp root that contains this package (bin/ -> package -> tool ->
/// repo root), falling back to the working directory.
String _defaultProjectRoot() {
  final root = Platform.script.resolve('../../..').toFilePath();
  if (Directory('$root/tool/supervisor_composition').existsSync()) {
    return root;
  }
  return Directory.current.path;
}
