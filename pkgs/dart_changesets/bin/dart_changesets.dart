import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:dart_changesets/dart_changesets.dart';

const changesetsDirName = '.changesets';
const configFileName = 'changesets.yaml';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addCommand('add')
    ..addCommand('status')
    ..addCommand(
      'version',
      ArgParser()..addFlag('check', negatable: false, help: 'Exit 1 when a version PR is due; write nothing.'),
    )
    ..addCommand('doctor', ArgParser()
      ..addFlag('no-network', negatable: false, help: 'Skip the pub.dev presence census.'))
    ..addCommand('tags')
    ..addCommand(
      'publish-tag',
      ArgParser()
        ..addOption('tag', help: 'Release tag, e.g. <package>-v<version>. Defaults to GITHUB_REF_NAME.')
        ..addFlag('execute', negatable: false, help: 'Publish for real (omit = preflight only).')
        ..addFlag('skip-existing', defaultsTo: true, help: 'Skip when pub.dev already exposes the version.'),
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } on ArgParserException catch (e) {
    stderr.writeln('dart_changesets: ${e.message}\n\n${parser.usage}');
    exit(64);
  }

  final repoRoot = findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln(
      'dart_changesets: no repository root found (looking for '
      '$configFileName or a $changesetsDirName directory upward).',
    );
    exit(64);
  }
  final config = ChangesetsConfig.loadFromFile(
    p.join(repoRoot.path, configFileName),
  );
  final graph = await WorkspaceGraph.load(repoRoot.path, config);
  final changesetsDir = p.join(repoRoot.path, changesetsDirName);

  switch (args.command!.name) {
    case 'add':
      exit(await runAdd(changesetsDir, graph, args.command!));
    case 'status':
      exit(await runStatus(changesetsDir, graph, config));
    case 'version':
      exit(await runVersion(
        repoRoot.path,
        changesetsDir,
        graph,
        config,
        checkOnly: args.command!['check'] as bool,
      ));
    case 'doctor':
      exit(await runDoctorCommand(
        graph,
        config,
        changesetsDir,
        census: !(args.command!['no-network'] as bool),
      ));
    case 'tags':
      exit(runTags(changesetsDir));
    case 'publish-tag':
      exit(await runPublishTag(
        repoRoot.path,
        graph,
        config,
        args.command!,
      ));
  }
}

Directory? findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, configFileName)).existsSync() ||
        Directory(p.join(dir.path, changesetsDirName)).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

// ---------------------------------------------------------------------------
// add
// ---------------------------------------------------------------------------

Future<int> runAdd(String changesetsDir, WorkspaceGraph graph, ArgResults args) async {
  final publishableNames = graph.publishable.map((pkg) => pkg.name).toList();
  if (publishableNames.isEmpty) {
    stderr.writeln('dart_changesets: no publishable packages found.');
    return 1;
  }

  final package = _promptPackage(publishableNames);
  if (package == null) return 1;
  final bump = _promptBump();
  if (bump == null) return 1;
  stdout.writeln('Summary (one line, empty line to finish):');
  final body = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
  if (body.isEmpty) {
    stderr.writeln('dart_changesets: empty summary — changeset discarded.');
    return 1;
  }

  final slug = _slugify(body);
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final path = p.join(changesetsDir, '${stamp}_$slug.md');
  Directory(changesetsDir).createSync(recursive: true);
  File(path).writeAsStringSync(
    "---\n'$package': ${bump.name}\n---\n\n$body\n",
  );
  stdout.writeln('OK: wrote $path');
  return 0;
}

String? _promptPackage(List<String> names) {
  stdout.writeln('Packages:');
  for (var i = 0; i < names.length; i++) {
    stdout.writeln('  ${i + 1}. ${names[i]}');
  }
  stdout.write('Pick one (name or number): ');
  final line = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
  if (line.isEmpty) return null;
  final asNumber = int.tryParse(line);
  if (asNumber != null && asNumber >= 1 && asNumber <= names.length) {
    return names[asNumber - 1];
  }
  if (names.contains(line)) return line;
  stderr.writeln('dart_changesets: "$line" is not a publishable package.');
  return null;
}

BumpType? _promptBump() {
  stdout.write('Bump type (major/minor/patch) [patch]: ');
  final line = stdin.readLineSync(encoding: utf8)?.trim().toLowerCase();
  if (line == null || line.isEmpty) return BumpType.patch;
  if (line == 'major' || line == 'minor' || line == 'patch') {
    return BumpType.fromString(line);
  }
  stderr.writeln('dart_changesets: "$line" is not a bump type.');
  return null;
}

String _slugify(String text) {
  final slug = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'changeset' : slug.substring(0, slug.length.clamp(0, 48));
}

// ---------------------------------------------------------------------------
// status
// ---------------------------------------------------------------------------

Future<int> runStatus(
  String changesetsDir,
  WorkspaceGraph graph,
  ChangesetsConfig config,
) async {
  final changesets = Changeset.loadPending(changesetsDir);
  if (changesets.isEmpty) {
    print('No pending changesets in $changesetsDir.');
    return 0;
  }
  print('Pending changesets (${changesets.length}):');
  for (final changeset in changesets) {
    final summary = changeset.bumps.entries
        .map((e) => '${e.key}: ${e.value.name}')
        .join(', ');
    print('  ${p.basename(changeset.path)}: $summary');
  }
  final plan = computePlan(graph: graph, changesets: changesets, config: config);
  if (plan.isEmpty) {
    print('Nothing to release.');
    return 0;
  }
  print('\nPlanned releases (dependency order):');
  for (final release in plan.releases) {
    final marker = release.isDependentBump ? ' (dependent)' : '';
    print(
      '  ${release.package.name} ${release.package.version} → '
      '${release.newVersion}$marker',
    );
    for (final entry in release.changelogEntries) {
      print('    - $entry');
    }
  }
  for (final error in plan.errors) {
    stderr.writeln('warning: $error');
  }
  return 0;
}

// ---------------------------------------------------------------------------
// version
// ---------------------------------------------------------------------------

Future<int> runVersion(
  String repoRoot,
  String changesetsDir,
  WorkspaceGraph graph,
  ChangesetsConfig config, {
  required bool checkOnly,
}) async {
  final changesets = Changeset.loadPending(changesetsDir);
  final plan = computePlan(graph: graph, changesets: changesets, config: config);
  for (final error in plan.errors) {
    stderr.writeln('warning: $error');
  }
  if (plan.isEmpty) {
    print('No pending changesets — nothing to release.');
    return 0;
  }
  if (checkOnly) {
    stdout.writeln('version PR due for ${plan.releases.length} package(s):');
    for (final release in plan.releases) {
      stdout.writeln(
        '  ${release.package.name} → ${release.newVersion.canonicalizedVersion}',
      );
    }
    return 1;
  }
  final applied = applyPlan(
    plan: plan,
    consumedChangesetPaths: changesets.map((c) => c.path).toList(),
    changesetsDir: changesetsDir,
    config: config,
    privateRewrites: plan.privateConstraintRewrites,
  );
  print('Wrote ${applied.writtenFiles.length} file(s):');
  for (final path in applied.writtenFiles) {
    print('  $path');
  }
  print('Consumed ${applied.consumedChangesets.length} changeset(s).');
  print('Tags for this train: ${File(applied.trainsFilePath).readAsLinesSync().first}');
  return 0;
}

// ---------------------------------------------------------------------------
// doctor
// ---------------------------------------------------------------------------

Future<int> runDoctorCommand(
  WorkspaceGraph graph,
  ChangesetsConfig config,
  String changesetsDir, {
  required bool census,
}) async {
  final report = await runDoctor(
    graph: graph,
    config: config,
    changesetsDir: changesetsDir,
    census: census,
  );
  print('Packages: ${graph.packages.length} total, '
      '${graph.publishable.length} publishable.');
  for (final finding in report.findings) {
    print(finding);
  }
  if (census) {
    final fresh = report.census.values
        .where((i) => i.status == PubDevStatus.newPackage)
        .length;
    final failed = report.census.values
        .where((i) => i.status == PubDevStatus.lookupFailed)
        .length;
    print(
      'pub.dev census: ${report.census.length - fresh - failed} existing, '
      '$fresh never-published (need manual first publish), $failed lookup errors.',
    );
    for (final entry in report.census.entries) {
      if (entry.value.status == PubDevStatus.newPackage) {
        print('  NEW: ${entry.key}');
      }
    }
  }
  if (report.hasErrors) {
    stderr.writeln('doctor: FAIL (${report.errorCount} error(s)).');
    return 1;
  }
  print('doctor: OK.');
  return 0;
}

// ---------------------------------------------------------------------------
// tags
// ---------------------------------------------------------------------------

int runTags(String changesetsDir) {
  final file = File(p.join(changesetsDir, pendingTrainFileName));
  if (!file.existsSync()) {
    stderr.writeln(
      'dart_changesets: no pending train ($pendingTrainFileName missing) — '
      'run `version` first.',
    );
    return 1;
  }
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  final tags = <String>[
    for (final entry in list)
      (entry as Map<String, dynamic>)['tag'] as String,
  ];
  print(jsonEncode(tags));
  return 0;
}

// ---------------------------------------------------------------------------
// publish-tag
// ---------------------------------------------------------------------------

Future<int> runPublishTag(
  String repoRoot,
  WorkspaceGraph graph,
  ChangesetsConfig config,
  ArgResults args,
) async {
  final tag =
      (args['tag'] as String?) ?? Platform.environment['GITHUB_REF_NAME'];
  if (tag == null || tag.isEmpty) {
    stderr.writeln(
      'dart_changesets: publish-tag requires --tag (or GITHUB_REF_NAME).',
    );
    return publishExitUsage;
  }
  return publishTag(
    repoRoot,
    config: config,
    graph: graph,
    tag: tag,
    execute: args['execute'] as bool,
    skipExisting: args['skip-existing'] as bool,
    pubDevClient: HttpPubDevClient(),
  );
}
